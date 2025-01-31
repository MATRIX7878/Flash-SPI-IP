LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY toplevel IS
    PORT(clk, MISO, reset: IN STD_LOGIC;
         MOSI, CS, flashClk, TX, mirrorMISO, mirrorCLK, mirrorMOSI, mirrorCS : OUT STD_LOGIC;
         LEDS : OUT STD_LOGIC_VECTOR (5 DOWNTO 0)
        );
END ENTITY;

ARCHITECTURE behavior OF toplevel IS
TYPE MEM IS (IDLE, RSTEN, RST, RSTCLK, REMS, SFDP, UID, RDID, WREN, PP, PPCLK, CE, CECLK, RECEIVE, SENDADDR, ADDR, SENDDATA, DATA);
SIGNAL currentMem : MEM;

TYPE LOC IS ARRAY (5 DOWNTO 0) OF STD_LOGIC_VECTOR (7 DOWNTO 0);
SIGNAL place : LOC;

CONSTANT CR : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0D"; --Carriage Return
CONSTANT LF : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0A"; --Line Feed
CONSTANT BS : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"08"; --Backspace
CONSTANT ESC : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"1B"; --Escape
CONSTANT SP : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"20"; --Space
CONSTANT DEL  : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"7F"; --Delete

SIGNAL flashReady : STD_LOGIC := '0';

SIGNAL charOut : STD_LOGIC_VECTOR (7 DOWNTO 0);

SIGNAL tx_data, tx_str, tx_start, tx_addr, tx_value : STD_LOGIC_VECTOR (7 DOWNTO 0);
SIGNAL tx_ready : STD_LOGIC;
SIGNAL tx_valid : STD_LOGIC := '0';

SIGNAL dataString : STRING (6 DOWNTO 1);
SIGNAL dataLogic : STD_LOGIC_VECTOR (47 DOWNTO 0);

SIGNAL startString : STRING (8 DOWNTO 1);
SIGNAL startLogic : STD_LOGIC_VECTOR (63 DOWNTO 0);

SIGNAL strCount : INTEGER RANGE 0 TO 9 := 0;
SIGNAL addrCount : INTEGER RANGE 0 TO 8 := 0;
SIGNAL dataCount : INTEGER RANGE 0 TO 4 := 0;

SIGNAL startData : STD_LOGIC_VECTOR (63 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataData : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');

SIGNAL CMD : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL currentState, returnState : state;

SIGNAL flashAddr : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
SIGNAL charIn : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS =>'0');

SIGNAL byteNum : INTEGER RANGE 0 TO 256;

SIGNAL counter : INTEGER RANGE 0 TO 5000 := 0;
SIGNAL RSTcounter : INTEGER RANGE 0 TO 811 := 0;
SIGNAL CEcounter : INTEGER RANGE 0 TO 324000000 := 0;
SIGNAL PPcounter : INTEGER RANGE 0 TO 10800 := 0;

COMPONENT UART_TX IS
    PORT (clk : IN  STD_LOGIC;
          reset : IN  STD_LOGIC;
          tx_valid : IN STD_LOGIC;
          tx_data : IN  STD_LOGIC_VECTOR (7 downto 0);
          tx_ready : OUT STD_LOGIC;
          tx_OUT : OUT STD_LOGIC);
END COMPONENT;

COMPONENT flash IS
    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 32));
-- GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10, 32)); For simulation
    PORT(clk, MISO : IN STD_LOGIC;
         CMD : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
         flashAddr : IN STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
         charIn : IN STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');
         currentState : IN state;
         byteNum : IN INTEGER RANGE 0 TO 256;
         flashClk, MOSI, flashReady : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0')
        );
END COMPONENT;

IMPURE FUNCTION BITSHIFT (input : STD_LOGIC_VECTOR) RETURN STD_LOGIC_VECTOR IS
    VARIABLE output : STD_LOGIC_VECTOR(7 DOWNTO 0);
    BEGIN
        FOR i IN 0 TO 7 LOOP
            output(i) := input(7 - i);
        END LOOP;
    RETURN output;
END FUNCTION;

IMPURE FUNCTION STR2SLV (str : STRING; size : STD_LOGIC_VECTOR) RETURN STD_LOGIC_VECTOR IS
    VARIABLE data : STD_LOGIC_VECTOR(size'length - 1 DOWNTO 0);
    BEGIN
    FOR i IN str'HIGH DOWNTO 1 LOOP
        data(i * 8 - 1 DOWNTO i * 8 - 8) := STD_LOGIC_VECTOR(TO_UNSIGNED(CHARACTER'POS(str(i)), 8));
    END LOOP;
    RETURN data;
END FUNCTION;

BEGIN
    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            mirrorMISO <= MISO;
            mirrorCLK <= flashClk;
            mirrorMOSI <= MOSI;
            mirrorCS <= CS;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            CASE currentMem IS
            WHEN IDLE => IF flashReady = '1' THEN
                currentMem <= RSTEN;
            ELSE
                currentState <= INIT;
                counter <= 0;
            END IF;
            WHEN RSTEN => CMD <= x"66";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= DONE;
                    currentMem <= RST;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN RST => CMD <= x"99";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= DONE;
                    currentMem <= RSTCLK;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN RSTCLK => IF RSTcounter = 810 THEN
                RSTcounter <= 0;
                currentMem <= REMS;
            ELSE
                RSTcounter <= RSTcounter + 1;
            END IF;
            WHEN REMS => CMD <= x"90";
                flashAddr <= x"000001";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= SEND;
                    byteNum <= 2;
                    counter <= counter + 1;
                ELSIF counter = 66 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 114 THEN
                    currentState <= DONE;
                    currentMem <= SFDP;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SFDP => CMD <= x"5A";
                flashAddr <= x"000010";
                charIn(2047 DOWNTO 2040) <= x"FF";
                charIn(2039 DOWNTO 0) <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 82 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 83 THEN
                    currentState <= SEND;
                    byteNum <= 255;
                    counter <= counter + 1;
                ELSIF counter = 100 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 4196 THEN
                    currentState <= DONE;
                    currentMem <= UID;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN UID => CMD <= x"4B";
                charIn(2047 DOWNTO 2016) <= x"FFFFFFFF";
                charIn(2015 DOWNTO 0) <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    byteNum <= 15;
                    counter <= counter + 1;
                ELSIF counter = 81 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 337 THEN
                    currentState <= DONE;
                    currentMem <= RDID;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN RDID => CMD <= x"9F";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    byteNum <= 2;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 65 THEN
                    currentState <= DONE;
                    currentMem <= WREN;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN WREN => CMD <= x"06";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= DONE;
                    currentMem <= CE;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN CE => CMD <= x"C7";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= DONE;
                    currentMem <= CECLK;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN CECLK => IF CEcounter = 323999999 THEN
                CEcounter <= 0;
                currentMem <= PP;
                LEDS <= (OTHERS => '0');
            ELSE
                CEcounter <= CEcounter + 1;
            END IF;
            WHEN PP => CMD <= x"02";
                byteNum <= 5;
                charIn(2047 DOWNTO 2000) <= x"1E5A9D3F6BC4";
                flashAddr <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 82 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 83 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 83 + byteNum * 16 THEN
                    currentMem <= PPCLK;
                    currentState <= DONE;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN PPCLK => IF PPcounter = 10799 THEN
                PPcounter <= 0;
                currentMem <= RECEIVE;
            ELSE
                PPcounter <= PPcounter + 1;
            END IF;
            WHEN RECEIVE => CMD <= x"03";
                byteNum <= 5;
                flashAddr <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 82 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 82 + byteNum * 16 THEN
                    currentMem <= SENDADDR;
                    currentState <= DONE;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDADDR => startString <= "Addr: 0x";
                startLogic <= STR2SLV(startString, startLogic);
                tx_data <= BITSHIFT(tx_start);
                IF tx_valid = '1' AND tx_ready = '1' AND strCount < 7 THEN
                    strCount <= strCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    strCount <= 0;
                    currentMem <= ADDR;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN ADDR => FOR i IN 7 DOWNTO 2 LOOP
                    startData(i * 8 + 7 DOWNTO i * 8) <= place(i - 2);
                END LOOP;
                startData(15 DOWNTO 0) <= CR & LF;
                tx_data <= BITSHIFT(tx_addr);
                IF tx_valid = '1' AND tx_ready = '1' AND addrCount < 7 THEN
                    addrCount <= addrCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    addrCount <= 0;
                    currentMem <= SENDDATA;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN SENDDATA => dataString <= "Data: ";
                dataLogic <= STR2SLV(dataString, dataLogic);
                tx_data <= BITSHIFT(tx_str);
                IF tx_valid = '1' AND tx_ready = '1' AND strCount < 5 THEN
                    strCount <= strCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    strCount <= 0;
                    currentMem <= DATA;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN DATA => dataData(23 DOWNTO 0) <= charOut & CR & LF;
                tx_data <= BITSHIFT(tx_value);
                IF tx_valid = '1' AND tx_ready = '1' AND dataCount < 2 THEN
                    dataCount <= dataCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    dataCount <= 0;
                    currentMem <= IDLE;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            END CASE;
        END IF;
    END PROCESS;

--    PROCESS(ALL)
--    BEGIN
--        IF RISING_EDGE(clk) THEN
--            tx_str <= dataLogic(47 - strCount * 8 DOWNTO 40 - strCount * 8);
--            tx_start <= startLogic(63 - strCount * 8 DOWNTO 56 - strCount * 8);
--            tx_addr <= startData(63 - addrCount * 8 DOWNTO 56 - addrCount * 8);
--            tx_value <= dataData(23 - dataCount * 8 DOWNTO 16 - dataCount * 8);
--        END IF;
--    END PROCESS;

    uarttx : UART_TX PORT MAP (clk => clk, reset => reset, tx_valid => tx_valid, tx_data => tx_data, tx_ready => tx_ready, tx_OUT => TX);
    memory : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10000000, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, byteNum => byteNum, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);
-- memory : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, byteNum => byteNum, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);

END ARCHITECTURE;

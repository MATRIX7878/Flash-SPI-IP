LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY top IS
    PORT(clk, MISO, reset: IN STD_LOGIC;
         MOSI, CS, flashClk, TX, mirrorCS, mirrorCLK, mirrorMOSI, mirrorMISO : OUT STD_LOGIC;
         LEDS : OUT STD_LOGIC_VECTOR (5 DOWNTO 0) := (OTHERS => '1')
        );
END ENTITY;

ARCHITECTURE behavior OF top IS
TYPE MEM IS (IDLE, RSTEN, RST, RSTCLK, REMS, SENDMID, MID, SENDDID, DID, SFDP);
SIGNAL currentMem : MEM := IDLE;

CONSTANT CR : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0D"; --Carriage Return
CONSTANT LF : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0A"; --Line Feed
CONSTANT BS : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"08"; --Backspace
CONSTANT ESC : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"1B"; --Escape
CONSTANT SP : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"20"; --Space
CONSTANT DEL  : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"7F"; --Delete

--Conversion variables--
SIGNAL char, hexHigh, hexLow : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');

--UART variables--
SIGNAL tx_ready : STD_LOGIC;
SIGNAL tx_valid : STD_LOGIC := '0';
SIGNAL tx_data, tx_str : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');

--UART strings--
SIGNAL deviceID : STRING (13 DOWNTO 1);
SIGNAL deviceLogic : STD_LOGIC_VECTOR (103 DOWNTO 0) := (OTHERS => '0');
SIGNAL manuID : STRING (14 DOWNTO 1);
SIGNAL manuLogic : STD_LOGIC_VECTOR (111 DOWNTO 0) := (OTHERS => '0');
SIGNAL IDData : STD_LOGIC_VECTOR (31 DOWNTO 0) := (OTHERS => '0');

--Flash states--
SIGNAL currentState : state := INIT;

--Top level counters--
SIGNAL counter : INTEGER RANGE 0 TO 324000000 := 0;

--Flash properties--
SIGNAL flashReady : STD_LOGIC := '0';
SIGNAL CMD : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL flashAddr : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
SIGNAL charIn : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS =>'0');
SIGNAL charOut : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS =>'0');

COMPONENT UARTTX IS
    PORT (clk : IN STD_LOGIC;
          reset : IN STD_LOGIC;
          tx_valid : IN STD_LOGIC;
          tx_data : IN STD_LOGIC_VECTOR (7 downto 0);
          tx_ready : OUT STD_LOGIC;
          tx_OUT : OUT STD_LOGIC);
END COMPONENT;

COMPONENT flash IS
    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 32));
    PORT(clk, MISO : IN STD_LOGIC;
         CMD : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
         flashAddr : IN STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
         charIn : IN STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');
         currentState : IN state;
         flashClk, MOSI, flashReady : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0')
        );
END COMPONENT;

COMPONENT conv IS
    PORT(clk : IN STD_LOGIC;
         char : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
         hexLow, hexHigh : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0')
        );
END COMPONENT;

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
            mirrorCS <= CS;
            mirrorCLK <= flashClk;
            mirrorMOSI <= MOSI;
            mirrorMISO <= MISO;

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
            WHEN RSTCLK => IF counter = 810 THEN
                counter <= 0;
                currentMem <= REMS;
            ELSE
                counter <= counter + 1;
            END IF;
            WHEN REMS => CMD <= x"90";
                flashAddr <= x"000000";
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
                ELSIF counter = 66 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 98 THEN
                    currentState <= DONE;
                    currentMem <= SENDMID;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDMID => manuID <= "Manufac ID: 0x";
                manuLogic <= STR2SLV(manuID, manuLogic);
                tx_data <= tx_str;
                char <= charOut(15 DOWNTO 8);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 13 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= MID;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN MID => IDData(31 DOWNTO 0) <= hexHigh & hexLow & CR & LF;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 3 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= SENDDID;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN SENDDID => deviceID <= "Device ID: 0x";
                deviceLogic <= STR2SLV(deviceID, deviceLogic);
                tx_data <= tx_str;
                char <= charOut(7 DOWNTO 0);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 12 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= DID;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN DID => IDData(31 DOWNTO 0) <= hexHigh & hexLow & CR & LF;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 3 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= SFDP;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN SFDP =>
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF currentMem = SENDMID THEN
                IF counter = 13 THEN
                    tx_str <= manuLogic(7 DOWNTO 0);
                ELSIF counter = 12 THEN
                    tx_str <= manuLogic(15 DOWNTO 8);
                ELSIF counter = 11 THEN
                    tx_str <= manuLogic(23 DOWNTO 16);
                ELSIF counter = 10 THEN
                    tx_str <= manuLogic(31 DOWNTO 24);
                ELSIF counter = 9 THEN
                    tx_str <= manuLogic(39 DOWNTO 32);
                ELSIF counter = 8 THEN
                    tx_str <= manuLogic(47 DOWNTO 40);
                ELSIF counter = 7 THEN
                    tx_str <= manuLogic(55 DOWNTO 48);
                ELSIF counter = 6 THEN
                    tx_str <= manuLogic(63 DOWNTO 56);
                ELSIF counter = 5 THEN
                    tx_str <= manuLogic(71 DOWNTO 64);
                ELSIF counter = 4 THEN
                    tx_str <= manuLogic(79 DOWNTO 72);
                ELSIF counter = 3 THEN
                    tx_str <= manuLogic(87 DOWNTO 80);
                ELSIF counter = 2 THEN
                    tx_str <= manuLogic(95 DOWNTO 88);
                ELSIF counter = 1 THEN
                    tx_str <= manuLogic(103 DOWNTO 96);
                ELSIF counter = 0 THEN
                    tx_str <= manuLogic(111 DOWNTO 104);
                END IF;
            END IF;

            IF currentMem = SENDDID THEN
                IF counter = 12 THEN
                    tx_str <= deviceLogic(7 DOWNTO 0);
                ELSIF counter = 11 THEN
                    tx_str <= deviceLogic(15 DOWNTO 8);
                ELSIF counter = 10 THEN
                    tx_str <= deviceLogic(23 DOWNTO 16);
                ELSIF counter = 9 THEN
                    tx_str <= deviceLogic(31 DOWNTO 24);
                ELSIF counter = 8 THEN
                    tx_str <= deviceLogic(39 DOWNTO 32);
                ELSIF counter = 7 THEN
                    tx_str <= deviceLogic(47 DOWNTO 40);
                ELSIF counter = 6 THEN
                    tx_str <= deviceLogic(55 DOWNTO 48);
                ELSIF counter = 5 THEN
                    tx_str <= deviceLogic(63 DOWNTO 56);
                ELSIF counter = 4 THEN
                    tx_str <= deviceLogic(71 DOWNTO 64);
                ELSIF counter = 3 THEN
                    tx_str <= deviceLogic(79 DOWNTO 72);
                ELSIF counter = 2 THEN
                    tx_str <= deviceLogic(87 DOWNTO 80);
                ELSIF counter = 1 THEN
                    tx_str <= deviceLogic(95 DOWNTO 88);
                ELSIF counter = 0 THEN
                    tx_str <= deviceLogic(103 DOWNTO 96);
                END IF;
            END IF;

            IF currentMem = MID OR currentMem = DID THEN
                IF counter = 3 THEN
                    tx_str <= IDData(7 DOWNTO 0);
                ELSIF counter = 2 THEN
                    tx_str <= IDData(15 DOWNTO 8);
                ELSIF counter = 1 THEN
                    tx_str <= IDData(23 DOWNTO 16);
                ELSIF counter = 0 THEN
                    tx_str <= IDData(31 DOWNTO 24);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    to_hex : conv PORT MAP (clk => clk, char => char, hexLow => hexLow, hexHigh => hexHigh);
    uart_tx : UARTTX PORT MAP (clk => clk, reset => reset, tx_valid => tx_valid, tx_data => tx_data, tx_ready => tx_ready, tx_OUT => TX);
--    memory : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10000000, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);
    memory : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);
END ARCHITECTURE;

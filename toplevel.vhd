LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;

ENTITY toplevel IS
    PORT(clk, MISO, btn1, btn2, RST: IN STD_LOGIC;
         MOSI, CS, flashClk, TX : OUT STD_LOGIC
        );
END ENTITY;

ARCHITECTURE behavior OF toplevel IS
TYPE state IS (IDLE, SENDADDR, ADDR, SENDDATA, DATA);
SIGNAL currentState : state;

TYPE LOC IS ARRAY (0 TO 5) OF STD_LOGIC_VECTOR (7 DOWNTO 0);
SIGNAL place : LOC;

CONSTANT CR : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0D"; --Carriage Return
CONSTANT LF : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0A"; --Line Feed
CONSTANT BS : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"08"; --Backspace
CONSTANT ESC : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"1B"; --Escape
CONSTANT SP : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"20"; --Space
CONSTANT DEL  : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"7F"; --Delete

SIGNAL btn1Reg : STD_LOGIC := '1';
SIGNAL btn2Reg : STD_LOGIC := '1';

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

SIGNAL nibble : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');

SIGNAL startData : STD_LOGIC_VECTOR (63 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataData : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');

COMPONENT UART_TX IS
    PORT (clk : IN  STD_LOGIC;
          reset : IN  STD_LOGIC;
          tx_valid : IN STD_LOGIC;
          tx_data : IN  STD_LOGIC_VECTOR (7 downto 0);
          tx_ready : OUT STD_LOGIC;
          tx_OUT : OUT STD_LOGIC);
END COMPONENT;

COMPONENT flash IS
--    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 32));
    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(100, 32));
    PORT(clk, MISO, button1, button2 : IN STD_LOGIC;
         flashClk, MOSI : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
         readAddr : OUT STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0')
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
        IF FALLING_EDGE(clk) THEN
            btn1Reg <= '1' WHEN btn1 ELSE '0';
            btn2Reg <= '1' WHEN btn2 ELSE '0';
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            CASE currentState IS
            WHEN IDLE => IF CS = '0' THEN
                currentState <= SENDADDR;
            END IF;
            WHEN SENDADDR => startString <= "Addr: 0x";
                startLogic <= STR2SLV(startString, startLogic);
                tx_data <= BITSHIFT(tx_start);
                FOR i IN 0 TO 5 LOOP
                    place(i) <= nibble(3 * i + 3 DOWNTO 3 * i) + TO_STDLOGICVECTOR(48, 8) WHEN nibble(3 * i + 3 DOWNTO 3 * i) <= 9 ELSE nibble(3 * i + 3 DOWNTO 3 * i) + TO_STDLOGICVECTOR(55, 8);
                END LOOP;
                IF tx_valid = '1' AND tx_ready = '1' AND strCount < 7 THEN
                    strCount <= strCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    strCount <= 0;
                    currentState <= ADDR;
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
                    currentState <= SENDDATA;
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
                    currentState <= DATA;
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
                    currentState <= IDLE;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            tx_str <= dataLogic(47 - strCount * 8 DOWNTO 40 - strCount * 8);
            tx_start <= startLogic(63 - strCount * 8 DOWNTO 56 - strCount * 8);
            tx_addr <= startData(63 - addrCount * 8 DOWNTO 56 - addrCount * 8);
            tx_value <= dataData(23 - dataCount * 8 DOWNTO 16 - dataCount * 8);
        END IF;
    END PROCESS;

    uarttx : UART_TX PORT MAP (clk => clk, reset => RST, tx_valid => tx_valid, tx_data => tx_data, tx_ready => tx_ready, tx_OUT => TX);
    memory : flash PORT MAP (clk => clk, MISO => MISO, button1 => btn1Reg, button2 => btn2Reg, flashClk => flashClk, MOSI => MOSI, CS => CS, charOut => charOut, readAddr => nibble);

END ARCHITECTURE;

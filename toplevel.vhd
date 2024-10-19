LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY toplevel IS
    PORT(clk, MISO, btn1, btn2, RST: IN STD_LOGIC;
         MOSI, CS, flashClk, TX : OUT STD_LOGIC
        );
END ENTITY;

ARCHITECTURE behavior OF toplevel IS
TYPE state IS (IDLE, SENDADDR, ADDR, SENDDATA, DATA);
SIGNAL currentState : state;

CONSTANT CR : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0D"; --Carriage Return
CONSTANT LF : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"0A"; --Line Feed
CONSTANT BS : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"08"; --Backspace
CONSTANT ESC : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"1B"; --Escape
CONSTANT SP : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"20"; --Space
CONSTANT DEL  : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"7F"; --Delete

SIGNAL btn1Reg : STD_LOGIC := '1';
SIGNAL btn2Reg : STD_LOGIC := '1';

SIGNAL charAddr : STD_LOGIC_VECTOR (5 DOWNTO 0) := (OTHERS => '0');
SIGNAL charOut : STD_LOGIC_VECTOR (7 DOWNTO 0);

SIGNAL tx_data, tx_str : STD_LOGIC_VECTOR (7 DOWNTO 0);
SIGNAL tx_ready : STD_LOGIC;
SIGNAL tx_valid : STD_LOGIC := '0';

SIGNAL dataString : STRING (6 DOWNTO 1);
SIGNAL dataLogic : STD_LOGIC_VECTOR (47 DOWNTO 0);

SIGNAL strCount : INTEGER := 0;

COMPONENT UART_TX IS
    PORT (clk : IN  STD_LOGIC;
          reset : IN  STD_LOGIC;
          tx_valid : IN STD_LOGIC;
          tx_data : IN  STD_LOGIC_VECTOR (7 downto 0);
          tx_ready : OUT STD_LOGIC;
          tx_OUT : OUT STD_LOGIC);
END COMPONENT;

COMPONENT flash IS
    PORT(clk, MISO, button1, button2 : IN STD_LOGIC;
         charAddr : IN STD_LOGIC_VECTOR (5 DOWNTO 0);
         flashClk : OUT STD_LOGIC := '0';
         MOSI : OUT STD_LOGIC := '0';
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

IMPURE FUNCTION STR2SLV (str : STRING) RETURN STD_LOGIC_VECTOR IS
    VARIABLE data : STD_LOGIC_VECTOR(47 DOWNTO 0);
    BEGIN
    FOR i IN 6 DOWNTO 1 LOOP
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
            WHEN SENDADDR => dataString <= "Addr: ";
                dataLogic <= STR2SLV(dataString);
                tx_data <= BITSHIFT(tx_str);
                IF tx_valid = '1' AND tx_ready = '1' AND strCount < 5 THEN
                    strCount <= strCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    strCount <= 0;
                    currentState <= ADDR;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN ADDR => currentState <= SENDDATA;
            WHEN SENDDATA => dataString <= "Data: ";
                dataLogic <= STR2SLV(dataString);
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND strCount < 5 THEN
                    strCount <= strCount + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    strCount <= 0;
                    currentState <= DATA;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN DATA => tx_data <= charOut;
                currentState <= IDLE;
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            tx_str <= dataLogic(47 - strCount * 8 DOWNTO 40 - strCount * 8);
        END IF;
    END PROCESS;

    uarttx : UART_TX PORT MAP (clk => clk, reset => RST, tx_valid => tx_valid, tx_data => tx_data, tx_ready => tx_ready, tx_OUT => TX);
    memory : flash PORT MAP (clk => clk, MISO => MISO, button1 => btn1Reg, button2 => btn2Reg, charAddr => charAddr, flashClk => flashClk, MOSI => MOSI, CS => CS, charOut => charOut);

END ARCHITECTURE;
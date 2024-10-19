LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;

ENTITY flash IS
--    GENERIC (STARTUP : STD_LOGIC_VECTOR (23 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 24));
    GENERIC (STARTUP : STD_LOGIC_VECTOR (23 DOWNTO 0) := TO_STDLOGICVECTOR(1000, 24));
    PORT(clk, MISO, button1, button2 : IN STD_LOGIC;
         charAddr : IN STD_LOGIC_VECTOR (5 DOWNTO 0);
         flashClk : OUT STD_LOGIC := '0';
         MOSI : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0')
        );
END ENTITY;

ARCHITECTURE behavior OF flash IS
TYPE state IS (INIT, LOADCMD, SEND, LOADADDR, READ, DONE);
SIGNAL currentState, returnState : state;

SIGNAL byteOut : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL byteNum : INTEGER RANGE 0 TO 32;
SIGNAL CMD : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"03";
SIGNAL readAddr : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataIn : STD_LOGIC_VECTOR (255 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataInBuff : STD_LOGIC_VECTOR (255 DOWNTO 0) := (OTHERS => '0');

SIGNAL dataReady : STD_LOGIC := '0';
SIGNAL bitsSend : STD_LOGIC_VECTOR (8 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataSend : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');

SIGNAL counter : STD_LOGIC_VECTOR (24 DOWNTO 0) := (OTHERS => '0');

BEGIN
    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            CASE currentState IS
            WHEN INIT => IF counter > STARTUP AND button1 = '1' AND button2 = '1' THEN
                counter <= (OTHERS => '0');
                byteOut <= (OTHERS => '0');
                byteNum <= 0;
                currentState <= LOADCMD;
            ELSE
                counter <= counter + '1';
            END IF;
            WHEN LOADCMD => CS <= '0';
                dataSend(23 DOWNTO 16) <= CMD;
                bitsSend <= TO_STDLOGICVECTOR(8, 9);
                currentState <= SEND;
                returnState <= LOADADDR;
            WHEN SEND => IF counter = 0 THEN
                flashClk <= '0';
                MOSI <= dataSend(23);
                dataSend <= dataSend(22 DOWNTO 0) & '0';
                bitsSend <= bitsSend - '1';
                counter <= TO_STDLOGICVECTOR(1, 25);
            ELSE
                counter <= (OTHERS => '0');
                flashClk <= '1';
                IF bitsSend = 0 THEN
                    currentState <= returnState;
                END IF;
            END IF;
            WHEN LOADADDR => dataSend <= readAddr;
                bitsSend <= TO_STDLOGICVECTOR(24, 9);
                currentState <= SEND;
                returnState <= READ;
                byteNum <= 0;
            WHEN READ => IF counter(0) = '0' THEN
                flashClk <= '0';
                counter <= counter + '1';
                IF counter(3 DOWNTO 0) = 0 AND counter > 0 THEN
                    dataIn((byteNum * 8 + 7) DOWNTO (byteNum * 8)) <= byteOut;
                    byteNum <= byteNum + 1;
                    IF byteNum = 31 THEN
                        currentState <= DONE;
                    END IF;
                END IF;
            ELSE
                flashClk <= '1';
                byteOut <= byteOut(6 DOWNTO 0) & MISO;
                counter <= counter + '1';
            END IF;
            WHEN DONE => dataReady <= '1';
                CS <= '1';
                dataInBuff <= dataIn;
                counter <= "0" & STARTUP;
                IF button1 = '0' THEN
                    readAddr <= readAddr + d"24";
                    currentState <= INIT;
                ELSIF button2 = '0' THEN
                    readAddr <= readAddr - d"24";
                    currentState <= INIT;
                END IF;
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            FOR i IN 0 TO 31 LOOP
                charOut <= TO_STDLOGICVECTOR(48, 8) + dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i)) WHEN dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i)) <= 9 ELSE TO_STDLOGICVECTOR(55, 8) + dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i));
            END LOOP;
        END IF;
    END PROCESS;
END ARCHITECTURE;
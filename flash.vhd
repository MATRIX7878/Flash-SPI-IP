LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY flash IS
--    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 32));
    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(100, 32));
    PORT(clk, MISO, button1, button2 : IN STD_LOGIC;
         CMD : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
         flashAddr : IN STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
         charIn : IN STD_LOGIC_VECTOR (255 DOWNTO 0) := (OTHERS => '0');
         currentState : IN state;
         flashClk, MOSI : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0')
        );
END ENTITY;

ARCHITECTURE Behavior OF flash IS
SIGNAL byteIn : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL byteOut : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL byteNum : INTEGER RANGE 0 TO 32;
SIGNAL dataIn : STD_LOGIC_VECTOR (255 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataInBuff : STD_LOGIC_VECTOR (255 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataOut : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataOutBuff : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');

SIGNAL dataReady : STD_LOGIC := '0';
SIGNAL dataSend : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');

SIGNAL counter : STD_LOGIC_VECTOR (32 DOWNTO 0) := (OTHERS => '0');

SIGNAL nextState : state;

BEGIN
    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            CASE currentState IS
            WHEN INIT => IF counter > STARTUP AND button1 = '1' AND button2 = '1' THEN
                counter <= (OTHERS => '0');
                byteOut <= (OTHERS => '0');
                byteNum <= 0;
                dataReady <= '0';
                CS <= '0';
            ELSE
                counter <= counter + '1';
            END IF;
            WHEN LOADCMD => dataSend(23 DOWNTO 16) <= CMD;
                CS <= '0';
            WHEN SEND => IF counter = 0 THEN
                flashClk <= '0';
                MOSI <= dataSend(23);
                dataSend <= dataSend(22 DOWNTO 0) & '0';
                counter <= TO_STDLOGICVECTOR(1, 33);
            ELSE
                counter <= (OTHERS => '0');
                flashClk <= '1';
            END IF;
            WHEN LOADADDR => dataSend <= flashAddr;
                byteNum <= 0;
                CS <= '0';
            WHEN READ => IF counter(0) = '0' THEN
                flashClk <= '0';
                counter <= counter + '1';
                IF counter(3 DOWNTO 0) = "0000" AND counter > "0" THEN
                    dataIn((byteNum * 8 + 7) DOWNTO (byteNum * 8)) <= byteOut;
                    byteNum <= byteNum + 1;
                END IF;
            ELSE
                flashClk <= '1';
                byteOut <= byteOut(6 DOWNTO 0) & MISO;
                counter <= counter + '1';
            END IF;
            WHEN WRITE => IF counter(0) = '0' THEN
                flashClk <= '0';
                counter <= counter + '1';
                IF counter(3 DOWNTO 0) = "0000" AND counter > "0" THEN
                    byteIn <= dataOut((byteNum * 8 + 7) DOWNTO (byteNum * 8));
                    byteNum <= byteNum + 1;
                END IF;
            ELSE
                flashClk <= '1';
                byteIn <= byteIn(6 DOWNTO 0) & MOSI;
                counter <= counter + '1';
            END IF;
            WHEN DONE => dataReady <= '1';
                CS <= '1';
                dataInBuff <= dataIn;
                dataOut <= dataOutBuff;
                counter <= "0" & STARTUP;
--                IF button1 = '0' THEN
--                    flashAddr <= flashAddr + TO_STDLOGICVECTOR(24, 24);
--                ELSIF button2 = '0' THEN
--                    flashAddr <= flashAddr - TO_STDLOGICVECTOR(24, 24);
--                END IF;
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            FOR i IN 0 TO 31 LOOP
                dataOutBuff <= TO_STDLOGICVECTOR(48, 8) + charIn((255 - 4 * i) DOWNTO (251 - 4 * i)) WHEN charIn((255 - 4 * i) DOWNTO (251 - 4 * i)) <= 9 ELSE TO_STDLOGICVECTOR(55, 8) + charIn((255 - 4 * i) DOWNTO (251 - 4 * i));
                charOut <= TO_STDLOGICVECTOR(48, 8) + dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i)) WHEN dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i)) <= 9 ELSE TO_STDLOGICVECTOR(55, 8) + dataInBuff((255 - 4 * i) DOWNTO (251 - 4 * i));
            END LOOP;
        END IF;
    END PROCESS;
END ARCHITECTURE;

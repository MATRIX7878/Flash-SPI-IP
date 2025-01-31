LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY flash IS
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
END ENTITY;

ARCHITECTURE Behavior OF flash IS
SIGNAL byteOut : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');

SIGNAL dataSend : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');

SIGNAL counter : STD_LOGIC_VECTOR (32 DOWNTO 0) := (OTHERS => '0');

SIGNAL numByte : INTEGER RANGE 0 TO 256;

SIGNAL nextState : state;

BEGIN
    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            CASE currentState IS
            WHEN INIT => IF counter > STARTUP THEN
                counter <= (OTHERS => '0');
                byteOut <= (OTHERS => '0');
                flashReady <= '1';
            ELSE
                counter <= counter + '1';
            END IF;
            WHEN LOADCMD => dataSend(2047 DOWNTO 2040) <= CMD;
            WHEN LOADADDR => dataSend(2047 DOWNTO 2024) <= flashAddr;
            WHEN LOADDATA => FOR i IN 255 DOWNTO 0 LOOP
                dataSend(8 * i + 7 DOWNTO 8 * i) <= charIn(8 * i + 7 DOWNTO 8 * i);
            END LOOP;
            WHEN SEND => CS <= '0';
                IF counter = 0 THEN
                    flashClk <= '1';
                    MOSI <= dataSend(2047);
                    dataSend <= dataSend(2046 DOWNTO 0) & '0';
                    counter <= counter + '1';
                ELSE
                    counter <= (OTHERS => '0');
                    flashClk <= '0';
                END IF;
            WHEN READ => IF counter(0) = '0' THEN
                flashClk <= '0';
                counter <= counter + '1';
                IF counter(3 DOWNTO 0) = "0000" AND counter > "0" THEN
                    charOut <= byteOut;
                END IF;
            ELSE
                flashClk <= '1';
                byteOut <= byteOut(6 DOWNTO 0) & MISO;
                counter <= counter + '1';
            END IF;
            WHEN DONE => CS <= '1';
                flashClk <= '0';
                counter <= "0" & STARTUP;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;

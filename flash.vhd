LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY flash IS
    GENERIC (STARTUP : STD_LOGIC_VECTOR (31 DOWNTO 0) := TO_STDLOGICVECTOR(10000000, 32));
    PORT(clk, MISO : IN STD_LOGIC;
         CMD : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
         flashAddr : IN STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
         charIn : IN STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');
         currentState : IN state;
         byteNum : IN INTEGER RANGE 0 TO 256;
         flashClk, MOSI : OUT STD_LOGIC := '0';
         CS : OUT STD_LOGIC := '1';
         charOut : OUT STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0')
        );
END ENTITY;

ARCHITECTURE Behavior OF flash IS
SIGNAL byteOut : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataIn : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');
SIGNAL dataInBuff : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');

SIGNAL dataReady : STD_LOGIC := '0';
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
                dataReady <= '0';
                CS <= '0';
            ELSE
                counter <= counter + '1';
            END IF;
            WHEN LOADCMD => dataSend(2047 DOWNTO 2040) <= CMD;
                CS <= '0';
            WHEN LOADADDR => dataSend(2047 DOWNTO 2024) <= flashAddr;
            WHEN LOADDATA => FOR i IN 255 DOWNTO 0 LOOP
                dataSend(8 * i + 7 DOWNTO 8 * i) <= charIn(8 * i + 7 DOWNTO 8 * i);
            END LOOP;
            WHEN SEND => numByte <= byteNum;
                IF counter = 0 THEN
                flashClk <= '0';
                MOSI <= dataSend(2047);
                dataSend <= dataSend(2046 DOWNTO 0) & '0';
                counter <= TO_STDLOGICVECTOR(1, 33);
            ELSE
                counter <= (OTHERS => '0');
                flashClk <= '1';
            END IF;
            WHEN READ => IF counter(0) = '0' THEN
                flashClk <= '0';
                counter <= counter + '1';
                IF counter(3 DOWNTO 0) = "0000" AND counter > "0" THEN
                    dataIn((byteNum * 8 + 7) DOWNTO (byteNum * 8)) <= byteOut;
                    numByte <= byteNum - 1;
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

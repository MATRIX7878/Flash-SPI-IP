LIBRARY IEEE, WORK;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;
USE WORK.flashStates.ALL;

ENTITY top IS
    PORT(clk, MISO, reset: IN STD_LOGIC;
         MOSI, CS, flashClk, TX, mirrorCS, mirrorCLK, mirrorMOSI, mirrorMISO : OUT STD_LOGIC := '1';
         LEDS : OUT STD_LOGIC_VECTOR (5 DOWNTO 0) := (OTHERS => '1')
        );
END ENTITY;

ARCHITECTURE behavior OF top IS
TYPE MEMORY IS (IDLE, CRLF, RSTEN, RST, RSTCLK, REMS, SENDMID, MID, SENDDID, DID, SFDP, SENDSFDP, PRINTSFDP, UID, SENDUID, PRINTUID, RDID, SENDMEM, MEM, SENDCAP, CAP, WREN, CE, CECLK, PP, PPCLK, FR, SENDADDR, ADDR, SENDDATA, DATA, DONE);
SIGNAL currentMem, returnMem : MEMORY := IDLE;

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
SIGNAL SFDPID : STRING (17 DOWNTO 1);
SIGNAL SFDPLogic : STD_LOGIC_VECTOR (135 DOWNTO 0) := (OTHERS => '0');
SIGNAL UIDID : STRING (11 DOWNTO 1);
SIGNAL UIDLogic : STD_LOGIC_VECTOR (87 DOWNTO 0) := (OTHERS => '0');
SIGNAL MEMID : STRING (15 DOWNTO 1);
SIGNAL MEMLogic : STD_LOGIC_VECTOR (119 DOWNTO 0) := (OTHERS => '0');
SIGNAL CAPID : STRING (12 DOWNTO 1);
SIGNAL CAPLogic : STD_LOGIC_VECTOR (95 DOWNTO 0) := (OTHERS => '0');
SIGNAL flashString : STRING (8 DOWNTO 1);
SIGNAL flashLogic : STD_LOGIC_VECTOR (63 DOWNTO 0) := (OTHERS => '0');

--Flash states--
SIGNAL currentState : state := INIT;

--Top level counters--
SIGNAL counter : INTEGER RANGE 0 TO 324000000 := 0;
SIGNAL sfdpCounter : INTEGER RANGE 1 TO 256 := 1;
SIGNAL uidCounter : INTEGER RANGE 1 TO 16 := 1;
SIGNAL addrCounter : INTEGER RANGE 1 TO 3 := 1;
SIGNAL dataCounter : INTEGER RANGE 1 TO 2048 := 1;

--Flash properties--
SIGNAL flashReady : STD_LOGIC := '0';
SIGNAL CMD : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');
SIGNAL flashAddr : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
SIGNAL charIn : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS =>'0');
SIGNAL charOut : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS =>'0');
SIGNAL IDData : STD_LOGIC_VECTOR (31 DOWNTO 0) := (OTHERS => '0');
SIGNAL propData : STD_LOGIC_VECTOR (23 DOWNTO 0) := (OTHERS => '0');
SIGNAL SFDPData : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');
SIGNAL UIDData : STD_LOGIC_VECTOR (127 DOWNTO 0) := (OTHERS => '0');
SIGNAL identData : STD_LOGIC_VECTOR (15 DOWNTO 0) := (OTHERS => '0');
SIGNAL SPACEDATA : STD_LOGIC_VECTOR (15 DOWNTO 0) := (OTHERS => '0');
SIGNAL FLASHDATA : STD_LOGIC_VECTOR (15 DOWNTO 0) := (OTHERS => '0');
SIGNAL storedData : STD_LOGIC_VECTOR (2047 DOWNTO 0) := (OTHERS => '0');

--Byte counter--
SIGNAL byteNum : INTEGER RANGE 1 TO 256 := 1;

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
            WHEN CRLF => SPACEDATA(15 DOWNTO 0) <= CR & LF;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 1 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= returnMem;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
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
                ELSIF counter = 18 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 19 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 68 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 100 THEN
                    currentState <= DONE;
                    currentMem <= SENDMID;
                    returnMem <= SENDDID;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDMID => manuID <= "Manufac ID: 0x";
                manuLogic <= STR2SLV(manuID, manuLogic);
                tx_data <= tx_str;
                IF returnMem = SENDDID THEN
                    char <= charOut(15 DOWNTO 8);
                ELSIF returnMem = SENDMEM THEN
                    char <= charOut(23 DOWNTO 16);
                END IF;
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
                    IF returnMem = SENDMEM THEN
                        currentMem <= CRLF;
                    ELSIF returnMem /= SENDMEM  THEN
                        currentMem <= returnMem;
                    END IF;
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
            WHEN SFDP => CMD <= x"5A";
                flashAddr <= x"000000";
                charIn(2047 DOWNTO 2040) <= x"FF";
                charIn(2039 DOWNTO 0) <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 19 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 66 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 67 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 84 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 4181 THEN
                    currentState <= DONE;
                    currentMem <= SENDSFDP;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDSFDP => SFDPID <= "SFDP Discovered: ";
                SFDPLogic <= STR2SLV(SFDPID, SFDPLogic);
                tx_data <= tx_str;
                SFDPData <= charOut;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 16 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    char <= SFDPData(2047 DOWNTO 2040);
                    SFDPData <= SFDPData(2039 DOWNTO 0) & x"00";
                    currentMem <= PRINTSFDP;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN PRINTSFDP => propData(23 DOWNTO 0) <= hexHigh & hexLow & SP;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 2 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    IF sfdpCounter = 256 THEN
                        sfdpCounter <= 1;
                        currentMem <= CRLF;
                        returnMem <= UID;
                    ELSIF sfdpCounter < 256 THEN
                        char <= SFDPData(2047 DOWNTO 2040);
                        SFDPData <= SFDPData(2039 DOWNTO 0) & x"00";
                        sfdpCounter <= sfdpCounter + 1;
                        currentMem <= PRINTSFDP;
                    END IF;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN UID => CMD <= x"4B";
                charIn(2047 DOWNTO 2016) <= x"FFFFFFFF";
                charIn(2015 DOWNTO 0) <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 17 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 84 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 340 THEN
                    currentState <= DONE;
                    currentMem <= SENDUID;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDUID => UIDID <= "Unique ID: ";
                UIDLogic <= STR2SLV(UIDID, UIDLogic);
                tx_data <= tx_str;
                UIDData <= charOut(127 DOWNTO 0);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 12 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    char <= UIDData(127 DOWNTO 120);
                    UIDData <= UIDData(119 DOWNTO 0) & x"00";
                    currentMem <= PRINTUID;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN PRINTUID => identData(15 DOWNTO 0) <= hexHigh & hexLow;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 1 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    IF uidCounter = 16 THEN
                        uidCounter <= 1;
                        currentMem <= CRLF;
                        returnMem <= RDID;
                    ELSIF uidCounter < 16 THEN
                        char <= UIDData(127 DOWNTO 120);
                        UIDData <= UIDData(119 DOWNTO 0) & x"00";
                        uidCounter <= uidCounter + 1;
                        currentMem <= PRINTUID;
                    END IF;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN RDID => CMD <= x"9F";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 67 THEN
                    currentState <= DONE;
                    currentMem <= SENDMID;
                    returnMem <= SENDMEM;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDMEM => MEMID <= "Memory Type: 0x";
                MEMLogic <= STR2SLV(MEMID, MEMLogic);
                tx_data <= tx_str;
                char <= charOut(15 DOWNTO 8);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 16 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= MEM;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN MEM => IDData(31 DOWNTO 0) <= hexHigh & hexLow & CR & LF;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 3 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= SENDCAP;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN SENDCAP => CAPID <= "Capacity: 0x";
                CAPLogic <= STR2SLV(CAPID, CAPLogic);
                tx_data <= tx_str;
                char <= charOut(7 DOWNTO 0);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 11 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= CAP;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN CAP => IDData(31 DOWNTO 0) <= hexHigh & hexLow & CR & LF;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 3 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= WREN;
                    returnMem <= CE;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN WREN => CMD <= x"06";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= DONE;
                    currentMem <= returnMem;
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
                ELSIF counter = 18 THEN
                    currentState <= DONE;
                    currentMem <= CECLK;
                    counter <= 0;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN CECLK => IF counter = 323999999 THEN
--            WHEN CECLK => IF counter = 32 THEN
                counter <= 0;
                LEDS <= (OTHERS => '1');
                currentMem <= WREN;
                returnMem <= PP;
            ELSE
                LEDS <= (OTHERS => '0');
                counter <= counter + 1;
            END IF;
            WHEN PP => CMD <= x"02";
                byteNum <= 6;
                charIn(2047 DOWNTO 2000) <= x"1E5A9D3F6BC4";
                flashAddr <= x"000000";
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 19 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 66 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 67 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 67 + byteNum * 16 THEN
                    counter <= 0;
                    currentMem <= PPCLK;
                    currentState <= DONE;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN PPCLK => IF counter = 10809 THEN
                counter <= 0;
                currentMem <= FR;
            ELSE
                counter <= counter + 1;
            END IF;
            WHEN FR => CMD <= x"0B";
                byteNum <= 6;
                flashAddr <= x"000000";
                charIn(2047 DOWNTO 2040) <= x"FF";
                charIn(2039 DOWNTO 0) <= (OTHERS => '0');
                IF counter = 0 THEN
                    currentState <= LOADCMD;
                    counter <= counter + 1;
                ELSIF counter = 1 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 18 THEN
                    currentState <= LOADADDR;
                    counter <= counter + 1;
                ELSIF counter = 19 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 66 THEN
                    currentState <= LOADDATA;
                    counter <= counter + 1;
                ELSIF counter = 67 THEN
                    currentState <= SEND;
                    counter <= counter + 1;
                ELSIF counter = 84 THEN
                    currentState <= READ;
                    counter <= counter + 1;
                ELSIF counter = 84 + byteNum * 16 THEN
                    counter <= 0;
                    currentMem <= SENDADDR;
                    currentState <= DONE;
                ELSE
                    counter <= counter + 1;
                END IF;
            WHEN SENDADDR => flashString <= "Addr: 0x";
                flashLogic <= STR2SLV(flashString, flashLogic);
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 7 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= ADDR;
                    char <= flashAddr(23 DOWNTO 16);
                    flashAddr <= flashAddr(15 DOWNTO 0) & x"00";
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN ADDR => FLASHDATA(15 DOWNTO 0) <= hexHigh & hexLow;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 1 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    IF addrCounter = 3 THEN
                        currentMem <= CRLF;
                        returnMem <= SENDDATA;
                        addrCounter <= 1;
                    ELSIF addrCounter < 3 THEN
                        char <= flashAddr(23 DOWNTO 16);
                        flashAddr <= flashAddr(15 DOWNTO 0) & x"00";
                        addrCounter <= addrCounter + 1;
                        currentMem <= ADDR;
                    END IF;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN SENDDATA => flashString <= "Data: 0x";
                flashLogic <= STR2SLV(flashString, flashLogic);
                tx_data <= tx_str;
                storedData(47 DOWNTO 0) <= charOut(47 DOWNTO 0);
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 7 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    currentMem <= DATA;
                    char <= storedData(47 DOWNTO 40);
                    storedData(47 DOWNTO 0) <= storedData(39 DOWNTO 0) & x"00";
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN DATA => FLASHDATA(15 DOWNTO 0) <= hexHigh & hexLow;
                tx_data <= tx_str;
                IF tx_valid = '1' AND tx_ready = '1' AND counter < 1 THEN
                    counter <= counter + 1;
                ELSIF tx_valid AND tx_ready THEN
                    tx_valid <= '0';
                    counter <= 0;
                    IF dataCounter = byteNum THEN
                        dataCounter <= 1;
                        currentMem <= DONE;
                    ELSIF dataCounter < byteNum THEN
                        char <= storedData(47 DOWNTO 40);
                        storedData(47 DOWNTO 0) <= storedData(39 DOWNTO 0) & x"00";
                        dataCounter <= dataCounter + 1;
                        currentMem <= DATA;
                    END IF;
                ELSIF NOT tx_valid THEN
                    tx_valid <= '1';
                END IF;
            WHEN DONE =>
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF currentMem = CRLF THEN
                IF counter = 1 THEN
                    tx_str <= SPACEDATA(7 DOWNTO 0);
                ELSIF counter = 0 THEN
                    tx_str <= SPACEDATA(15 DOWNTO 8);
                END IF;
            END IF;

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

            IF currentMem = MID OR currentMem = DID OR currentMem = MEM OR currentMem = CAP THEN
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

            IF currentMem = SENDSFDP THEN
                IF counter = 16 THEN
                    tx_str <= SFDPLogic(7 DOWNTO 0);
                ELSIF counter = 15 THEN
                    tx_str <= SFDPLogic(15 DOWNTO 8);
                ELSIF counter = 14 THEN
                    tx_str <= SFDPLogic(23 DOWNTO 16);
                ELSIF counter = 13 THEN
                    tx_str <= SFDPLogic(31 DOWNTO 24);
                ELSIF counter = 12 THEN
                    tx_str <= SFDPLogic(39 DOWNTO 32);
                ELSIF counter = 11 THEN
                    tx_str <= SFDPLogic(47 DOWNTO 40);
                ELSIF counter = 10 THEN
                    tx_str <= SFDPLogic(55 DOWNTO 48);
                ELSIF counter = 9 THEN
                    tx_str <= SFDPLogic(63 DOWNTO 56);
                ELSIF counter = 8 THEN
                    tx_str <= SFDPLogic(71 DOWNTO 64);
                ELSIF counter = 7 THEN
                    tx_str <= SFDPLogic(79 DOWNTO 72);
                ELSIF counter = 6 THEN
                    tx_str <= SFDPLogic(87 DOWNTO 80);
                ELSIF counter = 5 THEN
                    tx_str <= SFDPLogic(95 DOWNTO 88);
                ELSIF counter = 4 THEN
                    tx_str <= SFDPLogic(103 DOWNTO 96);
                ELSIF counter = 3 THEN
                    tx_str <= SFDPLogic(111 DOWNTO 104);
                ELSIF counter = 2 THEN
                    tx_str <= SFDPLogic(119 DOWNTO 112);
                ELSIF counter = 1 THEN
                    tx_str <= SFDPLogic(127 DOWNTO 120);
                ELSIF counter = 0 THEN
                    tx_str <= SFDPLogic(135 DOWNTO 128);
                END IF;
            END IF;

            IF currentMem = PRINTSFDP THEN
                IF counter = 2 THEN
                    tx_str <= propData(7 DOWNTO 0);
                ELSIF counter = 1 THEN
                    tx_str <= propData(15 DOWNTO 8);
                ELSIF counter = 0 THEN
                    tx_str <= propData(23 DOWNTO 16);
                END IF;
            END IF;

            IF currentMem = SENDUID THEN
                IF counter = 12 THEN
                    tx_str <= UIDLogic(7 DOWNTO 0);
                ELSIF counter = 11 THEN
                    tx_str <= UIDLogic(15 DOWNTO 8);
                ELSIF counter = 10 THEN
                    tx_str <= UIDLogic(23 DOWNTO 16);
                ELSIF counter = 9 THEN
                    tx_str <= UIDLogic(31 DOWNTO 24);
                ELSIF counter = 8 THEN
                    tx_str <= UIDLogic(39 DOWNTO 32);
                ELSIF counter = 7 THEN
                    tx_str <= UIDLogic(47 DOWNTO 40);
                ELSIF counter = 6 THEN
                    tx_str <= UIDLogic(55 DOWNTO 48);
                ELSIF counter = 5 THEN
                    tx_str <= UIDLogic(63 DOWNTO 56);
                ELSIF counter = 4 THEN
                    tx_str <= UIDLogic(71 DOWNTO 64);
                ELSIF counter = 3 THEN
                    tx_str <= UIDLogic(79 DOWNTO 72);
                ELSIF counter = 2 THEN
                    tx_str <= UIDLogic(87 DOWNTO 80);
                ELSIF counter = 1 THEN
                    tx_str <= LF;
                ELSIF counter = 0 THEN
                    tx_str <= CR;
                END IF;
            END IF;

            IF currentMem = PRINTUID THEN
                IF counter = 1 THEN
                    tx_str <= identData(7 DOWNTO 0);
                ELSIF counter = 0 THEN
                    tx_str <= identData(15 DOWNTO 8);
                END IF;
            END IF;

            IF currentMem = SENDMEM THEN
                IF counter = 16 THEN
                    tx_str <= MEMLogic(7 DOWNTO 0);
                ELSIF counter = 15 THEN
                    tx_str <= MEMLogic(15 DOWNTO 8);
                ELSIF counter = 14 THEN
                    tx_str <= MEMLogic(23 DOWNTO 16);
                ELSIF counter = 13 THEN
                    tx_str <= MEMLogic(31 DOWNTO 24);
                ELSIF counter = 12 THEN
                    tx_str <= MEMLogic(39 DOWNTO 32);
                ELSIF counter = 11 THEN
                    tx_str <= MEMLogic(47 DOWNTO 40);
                ELSIF counter = 10 THEN
                    tx_str <= MEMLogic(55 DOWNTO 48);
                ELSIF counter = 9 THEN
                    tx_str <= MEMLogic(63 DOWNTO 56);
                ELSIF counter = 8 THEN
                    tx_str <= MEMLogic(71 DOWNTO 64);
                ELSIF counter = 7 THEN
                    tx_str <= MEMLogic(79 DOWNTO 72);
                ELSIF counter = 6 THEN
                    tx_str <= MEMLogic(87 DOWNTO 80);
                ELSIF counter = 5 THEN
                    tx_str <= MEMLogic(95 DOWNTO 88);
                ELSIF counter = 4 THEN
                    tx_str <= MEMLogic(103 DOWNTO 96);
                ELSIF counter = 3 THEN
                    tx_str <= MEMLogic(111 DOWNTO 104);
                ELSIF counter = 2 THEN
                    tx_str <= MEMLogic(119 DOWNTO 112);
                ELSIF counter = 1 THEN
                    tx_str <= LF;
                ELSIF counter = 0 THEN
                    tx_str <= CR;
                END IF;
            END IF;

            IF currentMem = SENDCAP THEN
                IF counter = 11 THEN
                    tx_str <= CAPLogic(7 DOWNTO 0);
                ELSIF counter = 10 THEN
                    tx_str <= CAPLogic(15 DOWNTO 8);
                ELSIF counter = 9 THEN
                    tx_str <= CAPLogic(23 DOWNTO 16);
                ELSIF counter = 8 THEN
                    tx_str <= CAPLogic(31 DOWNTO 24);
                ELSIF counter = 7 THEN
                    tx_str <= CAPLogic(39 DOWNTO 32);
                ELSIF counter = 6 THEN
                    tx_str <= CAPLogic(47 DOWNTO 40);
                ELSIF counter = 5 THEN
                    tx_str <= CAPLogic(55 DOWNTO 48);
                ELSIF counter = 4 THEN
                    tx_str <= CAPLogic(63 DOWNTO 56);
                ELSIF counter = 3 THEN
                    tx_str <= CAPLogic(71 DOWNTO 64);
                ELSIF counter = 2 THEN
                    tx_str <= CAPLogic(79 DOWNTO 72);
                ELSIF counter = 1 THEN
                    tx_str <= CAPLogic(87 DOWNTO 80);
                ELSIF counter = 0 THEN
                    tx_str <= CAPLogic(95 DOWNTO 88);
                END IF;
            END IF;

            IF currentMem = SENDADDR OR currentMem = SENDDATA THEN
                IF counter = 7 THEN
                    tx_str <= flashLogic(7 DOWNTO 0);
                ELSIF counter = 6 THEN
                    tx_str <= flashLogic(15 DOWNTO 8);
                ELSIF counter = 5 THEN
                    tx_str <= flashLogic(23 DOWNTO 16);
                ELSIF counter = 4 THEN
                    tx_str <= flashLogic(31 DOWNTO 24);
                ELSIF counter = 3 THEN
                    tx_str <= flashLogic(39 DOWNTO 32);
                ELSIF counter = 2 THEN
                    tx_str <= flashLogic(47 DOWNTO 40);
                ELSIF counter = 1 THEN
                    tx_str <= flashLogic(55 DOWNTO 48);
                ELSIF counter = 0 THEN
                    tx_str <= flashLogic(63 DOWNTO 56);
                END IF;
            END IF;

            IF currentMem = ADDR OR currentMem = DATA THEN
                IF counter = 1 THEN
                    tx_str <= FLASHDATA(7 DOWNTO 0);
                ELSIF counter = 0 THEN
                    tx_str <= FLASHDATA(15 DOWNTO 8);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    to_hex : conv PORT MAP (clk => clk, char => char, hexLow => hexLow, hexHigh => hexHigh);
    uart_tx : UARTTX PORT MAP (clk => clk, reset => reset, tx_valid => tx_valid, tx_data => tx_data, tx_ready => tx_ready, tx_OUT => TX);
    storage : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10000000, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);
--    storage : flash GENERIC MAP (STARTUP => TO_STDLOGICVECTOR(10, 32)) PORT MAP (clk => clk, MISO => MISO, CMD => CMD, flashAddr => flashAddr, charIn => charIn, currentState => currentState, flashClk => flashClk, MOSI => MOSI, flashReady => flashReady, CS => CS, charOut => charOut);
END ARCHITECTURE;

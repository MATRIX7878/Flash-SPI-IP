LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;

ENTITY UARTTX IS
    GENERIC (DIVISOR : NATURAL := 234);
    PORT (clk : IN STD_LOGIC;
          reset : IN STD_LOGIC;
          tx_valid : IN STD_LOGIC;
          tx_data : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
          tx_ready : OUT STD_LOGIC;
          tx_OUT : OUT STD_LOGIC := '1');
END UARTTX;

ARCHITECTURE Behavior OF UARTTX IS
TYPE state IS (IDLE, START, SEND, STOP);
SIGNAL currentState, nextState : state;

CONSTANT BAUD : STD_LOGIC_VECTOR (7 DOWNTO 0) := TO_STDLOGICVECTOR(DIVISOR, 8);

SIGNAL bits, newBits : INTEGER RANGE 7 DOWNTO 0;
SIGNAL newReady, newOut, ready, leave : STD_LOGIC;
SIGNAL counter, newCounter : STD_LOGIC_VECTOR (7 DOWNTO 0);

BEGIN
    tx_ready <= ready;
    tx_OUT <= leave;

    PROCESS(ALL)
    BEGIN
        nextState <= currentState;
        newBits <= bits;
        newCounter <= counter;
        newReady <= ready;
        newOut <= leave;

        CASE currentState IS
        WHEN IDLE => newOut <= '1';
            newReady <= '0';
            IF tx_valid = '1' THEN
                nextState <= START;
            END IF;
        WHEN START => IF counter = BAUD THEN
            newOut <= '0';
            newCounter <= (OTHERS => '0');
            nextState <= SEND;
        ELSE
            newCounter <= counter + '1';
        END IF;
        WHEN SEND => IF counter = BAUD AND bits = 0 THEN
            newOut <= tx_data(7 - bits);
            newCounter <= (OTHERS => '0');
            nextState <= STOP;
        ELSIF counter = BAUD AND bits > 0 THEN
            newOut <= tx_data(7 - bits);
            newCounter <= (OTHERS => '0');
            newBits <= bits - 1;
        ELSE
            newCounter <= counter + '1';
        END IF;
        WHEN STOP => IF counter = BAUD THEN
            newBits <= 7;
            newReady <= '1';
            newOut <= '1';
            newCounter <= (OTHERS => '0');
            nextState <= IDLE;
        ELSE
            newCounter <= counter + '1';
        END IF;
        END CASE;

        IF reset THEN
            newReady <= '1';
            newOut <= '1';
            nextState <= IDLE;
            newBits <= 7;
            newCounter <= (OTHERS => '0');
        END IF;
    END PROCESS;

    PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            currentState <= nextState;
            bits <= newBits;
            counter <= newCounter;
            ready <= newReady;
            leave <= newOut;
        END IF;
    END PROCESS;
END ARCHITECTURE;

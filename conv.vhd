LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD_UNSIGNED.ALL;

ENTITY conv IS
    PORT (clk : IN STD_LOGIC;
          char : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
          hexHigh, hexLow : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
         );
END ENTITY;

ARCHITECTURE behavior OF conv IS
SIGNAL newHigh, newLow, upper, lower : STD_LOGIC_VECTOR (7 DOWNTO 0) := (OTHERS => '0');

BEGIN
    hexHigh <= upper;
    hexLow <= lower;

    PROCESS(ALL)
    BEGIN
        newHigh <= upper;
        newLow <= lower;
        newHigh <= char(7 DOWNTO 4) + TO_STDLOGICVECTOR(48, 8) WHEN char(7 DOWNTO 4) <= 9 ELSE char(7 DOWNTO 4) + TO_STDLOGICVECTOR(55, 8);
        newLow <= char(3 DOWNTO 0) + TO_STDLOGICVECTOR(48, 8) WHEN char(3 DOWNTO 0) <= 9 ELSE char(3 DOWNTO 0) + TO_STDLOGICVECTOR(55, 8);
    END PROCESS;

    PROCESS (ALL)
    BEGIN
        IF RISING_EDGE(clk) THEN
            upper <= newHigh;
            lower <= newLow;
        END IF;
    END PROCESS;
END ARCHITECTURE;

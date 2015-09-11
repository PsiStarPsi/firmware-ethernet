---------------------------------------------------------------------------------
-- Title         : 1000 BASE X ability match
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : Eth1000BaseXAbilityMatch.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Ability, acknowledge, consistency, idle match for Clause 37 auto-negotiation
-- Next pages are not supported.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity Eth1000BaseXAbilityMatch is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- System clock, reset & control
      ethRx62Clk       : in  sl;
      ethRx62Rst       : in  sl;
      -- Link is stable
      rxLinkSync       : in  sl;
      -- Entering a new state (abMatch should be reset on new state)
      newState         : in  sl;
      -- Output match signals
      abilityMatch     : out sl;
      ability          : out slv(15 downto 0);
      acknowledgeMatch : out sl;
      consistencyMatch : out sl;
      idleMatch        : out sl;
      -- Physical Interface Signals
      phyRxData        : in EthRxPhyLaneInType
   ); 

end Eth1000BaseXAbilityMatch;


-- Define architecture
architecture rtl of Eth1000BaseXAbilityMatch is
      
   type RegType is record
      ability      : slv(15 downto 0);
      abCount      : slv(2 downto 0);
      ackCount     : slv(2 downto 0);
      idleCount    : slv(2 downto 0);
      abMatch      : sl;
      ackMatch     : sl;
      consMatch    : sl;
      idleMatch    : sl;
      wordIsConfig : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      ability      => (others => '0'),
      abCount      => (others => '0'),
      ackCount     => (others => '0'),
      idleCount    => (others => '0'),
      abMatch      => '0',
      ackMatch     => '0',
      consMatch    => '0',
      idleMatch    => '0',
      wordIsConfig => '0'
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";

begin

   comb : process(r,phyRxData,ethRx62Rst,rxLinkSync,newState) is
      variable v : RegType;
   begin
      v := r;

      -- Check for /C1/ or /C2/
      if ( phyRxData.dataK = "01" and 
           (phyRxData.data = OS_C1_C or phyRxData.data = OS_C2_C)) then
         v.wordIsConfig := '1';
      else
         v.wordIsConfig := '0';
      end if;

      -- On /I1/ or /I2/, reset abCount and ackCount
      if ( phyRxData.dataK = "01" and 
           (phyRxData.data = OS_I1_C or phyRxData.dataK = OS_I2_C)) then
         v.abCount  := (others => '0');
         v.ackCount := (others => '0');
      -- If we just saw /C1/ or /C2/ the next word is the ability word
      elsif (r.wordIsConfig = '1') then
         v.ability := phyRxData.data;
         -- If the ability word doesn't match the last one, reset the counter
         -- Note we ignore the ack bit in this comparison
         if (v.ability(15) /= r.ability(15) or (v.ability(13 downto 0) /= r.ability(13 downto 0))) then
            v.abCount := (others => '0');
         -- Otherwise, we match.  Increment the ability count
         elsif (r.abCount < 3) then
            v.abCount := r.abCount + 1;
         end if;
         -- For acknowledge, need a match and the ack bit set or we reset
         if (v.ability /= r.ability or (r.ability(14) = '0')) then
            v.ackCount := (others => '0');
         -- Otherwise, we match.  Increment the ability count
         elsif (r.ackCount < 3) then
            v.ackCount := r.ackCount + 1;
         end if;      
      end if;

      -- On /C1/ or /C2/, reset idle count
      if ( r.wordIsConfig = '1' ) then
         v.idleCount  := (others => '0');
      -- If see /I1/ or /I2/ increment the idle count
      elsif (phyRxData.dataK = "01" and (phyRxData.data = OS_I1_C or phyRxData.data = OS_I2_C) ) then
         if (r.idleCount < 3) then
            v.idleCount := r.idleCount + 1;
         end if;
      end if;

      
      -- If the ability count is 3, we're matched
      if (r.abCount = 3) then
         v.abMatch := '1';
      -- Otherwise, we're not
      else
         v.abMatch := '0';
      end if;

      -- If the acknowledge count is 3, we're matched
      if (r.ackCount = 3) then
         v.ackMatch := '1';
      -- Otherwise, we're not
      else
         v.ackMatch := '0';
      end if;

      -- If the idle count is 3, we're matched
      if (r.idleCount = 3) then
         v.idleMatch := '1';
      -- Otherwise, we're not
      else
         v.idleMatch := '0';
      end if;      
      
      -- Check for consistency match
      if (v.abMatch = '1' and v.ackMatch = '1') then
         v.consMatch := '1';
      else
         v.consMatch := '0';
      end if;
      
      -- Reset on ethernet reset or sync down
      if (ethRx62Rst = '1' or rxLinkSync = '0' or newState = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      abilityMatch     <= r.abMatch;
      acknowledgeMatch <= r.ackMatch;
      consistencyMatch <= r.consMatch;
      idleMatch        <= r.idleMatch;
      ability          <= r.ability;
      
      rin <= v;

   end process;

   seq : process (ethRx62Clk) is
   begin
      if (rising_edge(ethRx62Clk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;


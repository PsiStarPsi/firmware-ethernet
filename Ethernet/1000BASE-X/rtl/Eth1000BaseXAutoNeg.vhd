---------------------------------------------------------------------------------
-- Title         : 1000 BASE X link autonegotiation
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : Eth1000BaseXAutoNeg.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Autonegotiation for 1000 BASE-X.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;

entity Eth1000BaseXAutoNeg is 
   generic (
      GATE_DELAY_G  : time                 := 1 ns;
      PIPE_STAGES_G : integer range 1 to 8 := 2;
      SIM_SPEEDUP_G : boolean              := false
   );
   port ( 
      -- GT user clock and reset (62.5 MHz)
      ethRx62Clk  : in  sl;
      ethRx62Rst  : in  sl;
      -- Autonegotiation is done
      autonegDone : out sl;
      -- Link is synchronized
      rxLinkSync  : in  sl;
      -- Physical Interface Signals
      phyRxData   : in  EthRxPhyLaneInType;
      phyTxData   : out EthTxPhyLaneOutType
   );
end Eth1000BaseXAutoNeg;

architecture rtl of Eth1000BaseXAutoNeg is

   type AutoNegStateType is (S_IDLE, S_AUTONEG_RESTART, S_ABILITY_DETECT,
                             S_ACK_DETECT, S_COMPLETE_ACK, S_FIRST_IDLE,
                             S_IDLE_DETECT, S_LINK_UP);

   type PhyRxDataArray is array (PIPE_STAGES_G-1 downto 0) of EthRxPhyLaneInType;
   
   type RegType is record
      autoNegState  : AutoNegStateType;
      rxDataPipe    : PhyRxDataArray;
      txData        : slv(15 downto 0);
      toggleC1C2    : sl;
      toggleWord    : sl;
      timerCnt      : slv(19 downto 0);
      sendIdle      : sl;
      useI1         : sl;
      linkUp        : sl;
      newState      : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      autoNegState  => S_IDLE,
      rxDataPipe    => (others => ETH_RX_PHY_LANE_IN_INIT_C),
      txData        => (others => '0'),
      toggleC1C2    => '0',
      toggleWord    => '0',
      timerCnt      => (others => '0'),
      sendIdle      => '0',
      useI1         => '0',
      linkUp        => '0',
      newState      => '0'
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- Signals for outputs from the match unit
   signal abilityMatch     : sl;
   signal acknowledgeMatch : sl;
   signal consistencyMatch : sl;
   signal idleMatch        : sl;
   signal ability          : slv(15 downto 0);

   constant LINK_TIMER_SIM_C  : natural := 625; -- 10 us at 62.5 MHz
   constant THIS_LINK_TIMER_C : natural := sel(SIM_SPEEDUP_G,LINK_TIMER_SIM_C,LINK_TIMER_C);
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";  
   
begin

   -- Match unit
   U_AbMatch : entity work.Eth1000BaseXAbilityMatch
      generic map (
         GATE_DELAY_G => GATE_DELAY_G)
      port map (
         ethRx62Clk        => ethRx62Clk,
         ethRx62Rst        => ethRx62Rst,
         rxLinkSync        => rxLinkSync,
         newState          => r.newState,
         abilityMatch      => abilityMatch,
         ability           => ability,
         acknowledgeMatch  => acknowledgeMatch,
         consistencyMatch  => consistencyMatch,
         idleMatch         => idleMatch,
         phyRxData         => r.rxDataPipe(PIPE_STAGES_G-1)
      );


   comb : process(r,phyRxData,ethRx62Rst,rxLinkSync,abilityMatch,
                  acknowledgeMatch,consistencyMatch,idleMatch,ability) is
      variable v : RegType;
   begin
      v := r;

      -- Pipeline for incoming data
      for i in PIPE_STAGES_G-1 downto 0 loop
         if (i /= 0) then
            v.rxDataPipe(i)    := v.rxDataPipe(i-1);
         else
            v.rxDataPipe(0)    := phyRxData;
         end if;
      end loop;      

      -- Toggle the configuration bit if toggleWord is 1
      if (r.toggleWord = '1') then
         v.toggleC1C2 := not(r.toggleC1C2);
      end if;
      -- Always switch between /C(1,2)/ and ConfigReg
      v.toggleWord := not(r.toggleWord);

      -- Choose what to send here (idle or configuration)
      if (r.sendIdle = '0') then
         if (r.toggleWord = '0') then
            if (r.toggleC1C2 = '0') then
               phyTxData.data  <= OS_C1_C;
               phyTxData.dataK <= "01";
            else
               phyTxData.data  <= OS_C2_C;
               phyTxData.dataK <= "01";
            end if;
         else
            phyTxData.data  <= r.txData;
            phyTxData.dataK <= "00";
         end if;
      else
         phyTxData.dataK <= "01";
         if (r.useI1 = '1') then
            phyTxData.data  <= OS_I1_C;
         else
            phyTxData.data  <= OS_I2_C;
         end if;
      end if;
      -- Regardless of what you're sending, the data is valid
      phyTxData.valid <= '1';
      
      -- Combinatorial state logic
      case(r.autoNegState) is
         -- Just transmit breaklink until you get a restart
         when S_IDLE =>
            v.txData      := OS_BL_C;
            v.sendIdle    := '0';
            v.timerCnt    := (others => '0');
            v.linkUp      := '0';
            if (rxLinkSync = '1') then
               v.autoNegState := S_AUTONEG_RESTART;
            end if;
         -- Transmit breaklink for 10 ms
         when S_AUTONEG_RESTART =>
            v.sendIdle    := '0';
            v.txData      := OS_BL_C;
            v.timerCnt    := r.timerCnt + 1;
            if (r.timerCnt > THIS_LINK_TIMER_C) then
               v.timerCnt     := (others => '0');
               v.autoNegState := S_ABILITY_DETECT;
            end if;
         -- Transmit own configuration with no ack
         -- Exit when we see 3 consistent non-breaklink configs
         when S_ABILITY_DETECT =>
            v.sendIdle    := '0';
            v.txData      := OS_CN_C;
            if (abilityMatch = '1' and ability /= 0) then
               v.autoNegState := S_ACK_DETECT;
            end if;
         -- Send configuration with ack bit
         -- Back to start on ackMatch and not(consistMatch)
         -- Success if we get ackMatch and consistencyMatch
         when S_ACK_DETECT => 
            v.sendIdle    := '0';
            v.txData      := OS_CA_C;
            if ( (acknowledgeMatch = '1' and consistencyMatch = '0') or 
                 (abilityMatch = '1' and ability = 0) ) then
               v.autoNegState := S_IDLE;
            elsif (acknowledgeMatch = '1' and consistencyMatch = '1') then
               v.autoNegState := S_COMPLETE_ACK;
            end if;
         -- Just send configuration with ack bit for timeout period 
         -- (we're not trying to do next pages [yet])
         when S_COMPLETE_ACK => 
            v.sendIdle    := '0';
            v.txData      := OS_CA_C;
            if (abilityMatch = '1' and ability = 0) then
               v.autoNegState := S_IDLE;
            end if;
            if (r.timerCnt < THIS_LINK_TIMER_C) then
               v.timerCnt     := r.timerCnt + 1;
            elsif (abilityMatch = '0' or ability /= 0) then
               v.timerCnt     := (others => '0');
               --v.autoNegState := S_FIRST_IDLE;
               v.autoNegState := S_IDLE_DETECT;
            end if;
         -- Send one I1 to flip disparity
         when S_FIRST_IDLE =>
            v.sendIdle := '1';
            v.useI1    := '1';
            v.autoNegState := S_IDLE_DETECT;
         -- Send idles
         when S_IDLE_DETECT =>
            v.sendIdle := '1';
            v.useI1    := '0';
            if (abilityMatch = '1' and ability = 0) then
               v.autoNegState := S_IDLE;
            end if;
            if (r.timerCnt < THIS_LINK_TIMER_C) then
               v.timerCnt     := r.timerCnt + 1;
            elsif (idleMatch = '1') then
               v.timerCnt     := (others => '0');
               v.autoNegState := S_LINK_UP;
            end if;
         when S_LINK_UP =>
            v.sendIdle := '1';
            v.linkUp   := '1';
            if (abilityMatch = '1') then
               v.autoNegState := S_IDLE;
            end if;            
         when others =>
      end case;

      -- If we lose sync, always go back to the start
      if (rxLinkSync = '0') then
         v.autoNegState := S_IDLE;
      end if;      
      
      -- Check for new state condition
      if (v.autoNegState /= r.autoNegState) then
         v.newState := '1';
      else 
         v.newState := '0';
      end if;
      
      -- Reset logic
      if (ethRx62Rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Connections to output ports
      autonegDone <= r.linkUp;
      
      rin <= v;

   end process;

   seq : process (ethRx62Clk) is
   begin
      if (rising_edge(ethRx62Clk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

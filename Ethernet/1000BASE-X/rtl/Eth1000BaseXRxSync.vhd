-------------------------------------------------------------------------------
-- Title         : 1000 BASE X link initialization
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : Eth1000BaseXRxSync.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Synchronization checker for 1000 BASE-X.
-------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;

entity Eth1000BaseXRxSync is 
   generic (
      GATE_DELAY_G  : time                 := 1 ns;
      PIPE_STAGES_G : integer range 1 to 8 := 2
   );
   port ( 
      -- GT user clock and reset (62.5 MHz)
      ethRx62Clk : in  sl;
      ethRx62Rst : in  sl;
      -- Local side has synchronization
      rxLinkSync  : out sl;
      -- Incoming data from GT
      phyRxData   : in EthRxPhyLaneInType
   ); 
end Eth1000BaseXRxSync;

-- Define architecture
architecture rtl of Eth1000BaseXRxSync is

   -- LOS : loss of sync
   -- CD  : combined CommaDetect / AcquireSync state
   -- SA  : sync acquired state   
   type InitStateType is (S_LOS, S_CD, S_SA);
   type PhyRxDataArray is array (PIPE_STAGES_G-1 downto 0) of EthRxPhyLaneInType;
   
   type RegType is record
      syncState  : InitStateType;
      rxDataPipe : PhyRxDataArray;
      rxLinkSync : sl;
      commaCnt   : slv(1 downto 0);
      cgGoodCnt  : slv(1 downto 0);
      cgBadCnt   : slv(1 downto 0);
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      syncState  => S_LOS,
      rxDataPipe => (others => ETH_RX_PHY_LANE_IN_INIT_C),
      rxLinkSync => '0',
      commaCnt   => (others => '0'),
      cgGoodCnt  => (others => '0'),
      cgBadCnt   => (others => '0')
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";  
   
begin

   comb : process(r,phyRxData,ethRx62Rst) is
      variable v : RegType;
   begin
      v := r;

      -- Pipeline for incoming data
      for i in PIPE_STAGES_G-1 downto 0 loop
         if (i /= 0) then
            v.rxDataPipe(i) := v.rxDataPipe(i-1);
         else
            v.rxDataPipe(0) := phyRxData;
         end if;
      end loop;
      

      -- Combinatorial state logic
      case(r.syncState) is
         -- Loss of Sync State
         when S_LOS =>
            v.rxLinkSync := '0';
            v.commaCnt   := (others => '0');
            v.cgGoodCnt  := (others => '0');
            v.cgBadCnt   := (others => '0');
            if (r.rxDataPipe(PIPE_STAGES_G-1).dataK(0) = '1' and 
                r.rxDataPipe(PIPE_STAGES_G-1).data(7 downto 0) = K_COM_C) then
               v.syncState := S_CD;
            end if;
         -- Comma detect state (should be aligned by GT to byte 0)
         -- Sync success after 3 commas in the low byte without errors.
         when S_CD =>
            if (r.rxDataPipe(PIPE_STAGES_G-1).decErr /= "00" or 
                r.rxDataPipe(PIPE_STAGES_G-1).dispErr /= "00") then
               v.syncState := S_LOS;
            elsif (r.rxDataPipe(PIPE_STAGES_G-1).dataK(0) = '1' and 
                   r.rxDataPipe(PIPE_STAGES_G-1).data(7 downto 0) = K_COM_C) then
               v.commaCnt := r.commaCnt + 1;
               if (r.commaCnt = "10") then
                  v.syncState := S_SA;
               end if;
            end if;
         -- Sync acquired state
         -- Monitor for:  1) cggood: valid data or a comma with rx false
         --               2) cgbad:  !valid data or comma in wrong position
         when S_SA =>
            v.rxLinkSync := '1';
            -- Bad code group conditions: 
            --  - decode error
            --  - disparity error
            --  - comma in wrong byte
            if (r.rxDataPipe(PIPE_STAGES_G-1).decErr /= "00" or 
                r.rxDataPipe(PIPE_STAGES_G-1).dispErr /= "00" or 
                (r.rxDataPipe(PIPE_STAGES_G-1).dataK = "10" and 
                 r.rxDataPipe(PIPE_STAGES_G-1).data(15 downto 8) = K_COM_C)) then
                  if (r.cgBadCnt = "11") then
                     v.syncState := S_LOS;
                  else
                     v.cgBadCnt := r.cgBadCnt + 1;
                  end if;
            else
               if (r.cgBadCnt > 0) then
                  if (r.cgGoodCnt = "11") then
                     v.cgBadCnt  := r.cgBadCnt - 1;
                     v.cgGoodCnt := "00";
                  else
                     v.cgGoodCnt := r.cgGoodCnt + 1;
                  end if;
               end if;
            end if;
         -- Others
         when others =>
            v.syncState := S_LOS;
      end case;

      if (ethRx62Rst = '1') then
         v := REG_INIT_C;
      end if;
      
      rin <= v;

      rxLinkSync <= r.rxLinkSync;
      
   end process;

   seq : process (ethRx62Clk) is
   begin
      if (rising_edge(ethRx62Clk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;


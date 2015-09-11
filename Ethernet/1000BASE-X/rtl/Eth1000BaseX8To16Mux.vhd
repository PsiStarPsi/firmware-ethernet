--------------------------------------------------------------------
-- Title      : 1000 BASE X (16-bit) to 8-bit MAC width translation
--------------------------------------------------------------------
-- File       : Eth1000BaseX8To16Mux.vhd
-- Author     : Kurtis Nishimura 
-------------------------------------------------------------------------------
-- Description: Width translation for outgoing data
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
--use ieee.numeric_std.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

library UNISIM;
use UNISIM.VCOMPONENTS.all;

entity Eth1000BaseX8To16Mux is
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port (
      -- Clocking to deal with the GT data out (62.5 MHz)
      eth62Clk      : in  sl;
      eth62Rst      : in  sl;
      -- 125 MHz clock for 8 bit inputs
      eth125Clk     : in  sl;
      eth125Rst     : in  sl;
      -- PHY (16 bit) data interface out
      ethPhyDataOut : out EthTxPhyLaneOutType;
      -- MAC (8 bit) data interface out
      ethMacDataIn  : in  EthMacDataType
   );
end Eth1000BaseX8To16Mux;

-- Define architecture
architecture rtl of Eth1000BaseX8To16Mux is

   type StateType is (SYNC_S, HIGH_S, LOW_S);

   type RegType is record
      state     : StateType;
      phyTxData : EthTxPhyLaneOutType;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state     => SYNC_S,
      phyTxData => ETH_TX_PHY_LANE_OUT_INIT_C
   );

   signal r     : RegType := REG_INIT_C;
   signal rin   : RegType;
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";     
   
begin

   comb : process(r,eth125Rst,ethMacDataIn) is
      variable v : RegType;
   begin
      v := r;

      -- Clear any pulsed signals
      v.phyTxData.valid := '0';
      
      -- Combinatorial state logic
      case(r.state) is
         -- We want to ensure proper alignment of the commas
         when SYNC_S =>
            if ethMacDataIn.dataValid = '1' and ethMacDataIn.dataK = '1' then
               v.state := HIGH_S;
            end if;
         -- Set the high byte
         when HIGH_S =>
            v.phyTxData.data(15 downto 8) := ethMacDataIn.data;
            v.phyTxData.dataK(1)          := ethMacDataIn.dataK;
            v.phyTxData.valid             := '1';
            v.state                       := LOW_S;
         -- Set the low byte and write to the FIFO
         when LOW_S =>
            v.phyTxData.data( 7 downto 0) := ethMacDataIn.data;
            v.phyTxData.dataK(0)          := ethMacDataIn.dataK;
            v.phyTxData.valid             := '0';
            v.state                       := HIGH_S;
         when others =>
            v.state := SYNC_S;
      end case;
      
      -- Reset logic
      if (eth125Rst = '1') then
         v := REG_INIT_C;
      end if;
      
      -- Map to outputs
      
      -- Assignment to signal
      rin <= v;
      
   end process;

   seq : process (eth125Clk) is
   begin
      if (rising_edge(eth125Clk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;      
   
   -- FIFO to cross the two clock domains
   U_Fifo18x16 : entity work.fifo18x16
      port map (
         rst                => eth125Rst,
         wr_clk             => eth125Clk,
         rd_clk             => eth62Clk,
         din(17 downto 16)  => r.phyTxData.dataK,
         din(15 downto  0)  => r.phyTxData.data,
         wr_en              => r.phyTxData.valid,
         rd_en              => '1',
         dout(17 downto 16) => ethPhyDataOut.dataK,
         dout(15 downto  0) => ethPhyDataOut.data,
         full               => open,
         empty              => open,
         valid              => ethPhyDataOut.valid
      );
   
end rtl;

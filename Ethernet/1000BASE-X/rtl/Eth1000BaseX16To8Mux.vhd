--------------------------------------------------------------------
-- Title      : 1000 BASE X (16-bit) to 8-bit MAC width translation
--------------------------------------------------------------------
-- File       : Eth1000BaseX16To8Mux.vhd
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

entity Eth1000BaseX16To8Mux is
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
      -- PHY (16 bit) data interface
      ethPhyDataIn  : in  EthRxPhyLaneInType;
      -- MAC (8 bit) data interface
      ethMacDataOut : out EthMacDataType
   );
end Eth1000BaseX16To8Mux;

-- Define architecture
architecture rtl of Eth1000BaseX16To8Mux is

   type StateType is (SYNC_S, HIGH_S, LOW_S);

   type RegType is record
      state     : StateType;
      phyTxData : EthTxPhyLaneOutType;
      rdEn      : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state     => SYNC_S,
      phyTxData => ETH_TX_PHY_LANE_OUT_INIT_C,
      rdEn      => '0'
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;
   
   signal localPhyData : EthRxPhyLaneInType;
   signal validPipe    : slv(1 downto 0);
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";     
   
begin

   comb : process(r,eth125Rst,ethPhyDataIn,validPipe, localPhyData) is
      variable v : RegType;
   begin
      v := r;

      -- Clear any pulsed signals
      ethMacDataOut.data      <= (others => '0');
      ethMacDataOut.dataK     <= '0';
      ethMacDataOut.dataValid <= '0';
      
      -- Combinatorial state logic
      case(r.state) is
         -- Synchronize to last valid read of FIFO 
         when SYNC_S =>
            v.rdEn := '1';
            if validPipe(1) = '1' and validPipe(0) = '0' then
               v.state := HIGH_S;
            end if;
         -- Grab high word
         when HIGH_S =>
            v.rdEn                  := '0';
            ethMacDataOut.data      <= localPhyData.data(15 downto 8);
            ethMacDataOut.dataK     <= localPhyData.dataK(1);
            ethMacDataOut.dataValid <= '1';
            v.state                 := LOW_S;
         -- Grab low word
         when LOW_S =>
            v.rdEn                  := '1';
            ethMacDataOut.data      <= localPhyData.data(7 downto 0);
            ethMacDataOut.dataK     <= localPhyData.dataK(0);
            ethMacDataOut.dataValid <= '1';
            v.state                 := HIGH_S;
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
         rst                => eth62Rst,
         wr_clk             => eth62Clk,
         rd_clk             => eth125Clk,
         din(17 downto 16)  => ethPhyDataIn.dataK,
         din(15 downto  0)  => ethPhyDataIn.data,
         wr_en              => '1',
         rd_en              => r.rdEn,
         dout(17 downto 16) => localPhyData.dataK,
         dout(15 downto  0) => localPhyData.data,
         full               => open,
         empty              => open,
         valid              => validPipe(0)
      );
   
   -- Basic pipeline for the valid signal
   process(eth125Clk) begin
      if rising_edge(eth125Clk) then
         if eth125Rst = '1' then
            validPipe(1) <= '1';
         else
            validPipe(1) <= validPipe(0);
         end if;
      end if;
   end process;
   
end rtl;

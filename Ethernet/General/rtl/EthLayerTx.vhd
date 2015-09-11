---------------------------------------------------------------------------------
-- Title         : Ethernet Layer TX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : EthFrameTx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to GTP interface to 1000 BASE X Ethernet.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity EthFrameTx is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk          : in  sl;
      ethTxRst          : in  sl := '0';
      -- Data for the header
      ethTxDestMac      : in  MacAddrType := MAC_ADDR_DEFAULT_C;
      ethTxSrcMac       : in  MacAddrType := MAC_ADDR_INIT_C;
      ethTxEtherType    : in  EtherType;
      -- User data to be sent
      ethTxDataIn       : in  slv(7 downto 0);
      ethTxDataValid    : in  sl;
      ethTxDataLastByte : in  sl;
      ethTxDataReady    : out sl;
      -- Data output
      macTxDataOut      : out slv(7 downto 0);
      macTxDataValid    : out sl;
      macTxDataLastByte : out sl;
      macTxDataReady    : in  sl
   ); 
end EthFrameTx;

architecture rtl of EthFrameTx is

   type StateType is (IDLE_S, DEST_MAC_S, SRC_MAC_S, ETHERTYPE_S, DATA_S);
   
   type RegType is record
      state             : StateType;
      ethTxDestMac      : MacAddrType;
      ethTxSrcMac       : MacAddrType;
      ethTxEtherType    : EtherType;
      ethTxDataReady    : sl;
      macTxDataOut      : slv(7 downto 0);
      macTxDataValid    : sl;
      macTxDataLastByte : sl;
      byteCounter       : slv(3 downto 0);
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state             => IDLE_S,             
      ethTxDestMac      => MAC_ADDR_INIT_C,
      ethTxSrcMac       => MAC_ADDR_INIT_C,
      ethTxEtherType    => (others => '0'),
      ethTxDataReady    => '0',
      macTxDataOut      => (others => '0'),
      macTxDataValid    => '0',
      macTxDataLastByte => '0',
      byteCounter       => (others => '0')
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

   comb : process(r,ethTxRst,ethTxDestMac,ethTxSrcMac,ethTxEtherType,
                  ethTxDataIn,ethTxDataValid,ethTxDataLastByte,
                  macTxDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      ethTxDataReady      <= '0';
      v.ethTxDataReady    := '0';
      v.macTxDataValid    := '0';
      v.macTxDataLastByte := '0';
      
      -- State machine
--      if (macTxDataReady = '1') then
      case(r.state) is 
         when IDLE_S =>
            if (ethTxDataValid = '1' and macTxDataReady = '1') then
               v.ethTxDestMac   := ethTxDestMac;
               v.ethTxSrcMac    := ethTxSrcMac;
               v.ethTxEtherType := ethTxEtherType;
               v.byteCounter    := (others => '0');
               v.state          := DEST_MAC_S;
            end if;
         when DEST_MAC_S =>
            v.macTxDataOut   := r.ethTxDestMac(5-conv_integer(r.byteCounter));
            v.macTxDataValid := '1';
            if (macTxDataReady = '1') then
               v.byteCounter    := r.byteCounter + 1;
               --v.macTxDataOut   := r.ethTxDestMac(5-conv_integer(v.byteCounter));
               if (r.byteCounter = 5) then
                  v.byteCounter := (others => '0');
                  v.state       := SRC_MAC_S;
               end if;
            end if;
         when SRC_MAC_S =>
            v.macTxDataOut   := r.ethTxSrcMac(5-conv_integer(r.byteCounter));
            v.macTxDataValid := '1';
            if (macTxDataReady = '1') then
               v.byteCounter    := r.byteCounter + 1;
               if (r.byteCounter = 5) then
                  v.byteCounter := (others => '0');
                  v.state       := ETHERTYPE_S;
               end if;
            end if;
         when ETHERTYPE_S =>
            v.macTxDataOut   := getByte(1-conv_integer(r.byteCounter),r.ethTxEtherType);
            v.macTxDataValid := '1';
            if (macTxDataReady = '1') then
               v.byteCounter    := r.byteCounter + 1;
               if (r.byteCounter = 1) then
                  v.ethTxDataReady := macTxDataReady;
                  v.byteCounter    := (others => '0');
                  v.state          := DATA_S;
               end if;
            end if;
         when DATA_S =>
            ethTxDataReady      <= macTxDataReady;
            v.ethTxDataReady    := macTxDataReady;
            v.macTxDataOut      := ethTxDataIn;
            v.macTxDataValid    := ethTxDataValid;
            v.macTxDataLastByte := ethTxDataLastByte;
            if (r.macTxDataValid = '1' and r.macTxDataLastByte = '1' and macTxDataReady = '1') then
               v.state          := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
--      end if;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
--      ethTxDataReady    <= r.ethTxDataReady;
      macTxDataOut      <= r.macTxDataOut;
      macTxDataValid    <= r.macTxDataValid;
      macTxDataLastByte <= r.macTxDataLastByte;
      
      -- Assign variable to signal
      rin <= v;

   end process;

   seq : process (ethTxClk) is
   begin
      if (rising_edge(ethTxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

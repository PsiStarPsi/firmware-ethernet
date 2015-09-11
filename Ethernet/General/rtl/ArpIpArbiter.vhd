---------------------------------------------------------------------------------
-- Title         : Arbiter between ARP and IPv4
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : ArpIpArbiter.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Prioritizes responding to ARP requests.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity ArpIpArbiter is 
   generic (
      GATE_DELAY_G : in time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk          : in  sl;
      ethTxRst          : in  sl;
      -- ARP request/ack, data interface
      arpTxReq          : in  sl;
      arpTxAck          : in  sl;
      arpTxData         : in  slv(7 downto 0);
      arpTxDataValid    : in  sl;
      arpTxDataLastByte : in  sl;
      arpTxDataReady    : out sl;
      -- IPv4 request/ack, data interface
      ipTxData          : in  slv(7 downto 0);
      ipTxDataValid     : in  sl;
      ipTxDataLastByte  : in  sl;
      ipTxDataReady     : out sl;
      -- Output MUXed data
      ethTxEtherType    : out EtherType;
      ethTxData         : out slv(7 downto 0);
      ethTxDataValid    : out sl;
      ethTxDataLastByte : out sl;
      ethTxDataReady    : in  sl
   ); 
end ArpIpArbiter;

architecture rtl of ArpIpArbiter is

   type StateType is (IDLE_S, WAIT_ARP_S, WAIT_IP_S, FINISH_ARP_S);
   
   type RegType is record
      state : StateType;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state => IDLE_S
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

   comb : process(r,ethTxRst,arpTxReq,arpTxAck,arpTxData,arpTxDataValid,arpTxDataLastByte,
                  ipTxData,ipTxDataValid,ipTxDataLastByte,ethTxDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      ethTxEtherType    <= (others => '0');
      ethTxData         <= (others => '0');
      ethTxDataValid    <= '0';
      ethTxDataLastByte <= '0';
      arpTxDataReady    <= '0';
      ipTxDataReady     <= '0';
      
      -- State machine
      case(r.state) is 
         -- Ready should be zero for all possible output types
         -- If we see an ARP request, go ahead with it
         -- (if we want to add ICMP, put it here)
         -- Otherwise, default to IP data
         when IDLE_S =>
            if (arpTxReq = '1') then
               v.state := WAIT_ARP_S;
            elsif ipTxDataValid = '1' then
               v.state := WAIT_IP_S;
            end if;
         when WAIT_ARP_S =>
            ethTxEtherType    <= ETH_TYPE_ARP_C;
            ethTxData         <= arpTxData;
            ethTxDataValid    <= arpTxDataValid;
            ethTxDataLastByte <= arpTxDataLastByte;
            arpTxDataReady    <= ethTxDataReady;
            if arpTxAck = '1' then
               v.state := FINISH_ARP_S;
            end if;
         when WAIT_IP_S =>
            ethTxEtherType    <= ETH_TYPE_IPV4_C;
            ethTxData         <= ipTxData;
            ethTxDataValid    <= ipTxDataValid;
            ethTxDataLastByte <= ipTxDataLastByte;
            ipTxDataReady     <= ethTxDataReady;
            -- Byte was valid, last, and accepted
            if ipTxDataValid = '1' and ipTxDataLastByte = '1' and ethTxDataReady = '1' then
               v.state := IDLE_S;
            end if;
         when FINISH_ARP_S =>
            if arpTxReq = '0' then
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      
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

---------------------------------------------------------------------------------
-- Title         : ARP Responder
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : ArpResponder.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Receives ARP requests, sends back ARP responses.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity ArpResponder is 
   generic (
      NUM_IP_G     : integer := 1;
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethClk         : in  sl;
      ethRst         : in  sl := '0';
      -- Local MAC/IP settings
      macAddress     : in  MacAddrType;
      ipAddresses    : in  IpAddrArray(NUM_IP_G-1 downto 0);
      -- Connection to ARP RX
      arpRxOp        : in  slv(15 downto 0);
      arpRxSenderMac : in  MacAddrType;
      arpRxSenderIp  : in  IpAddrType;
      arpRxTargetMac : in  MacAddrType;
      arpRxTargetIp  : in  IpAddrType;
      arpRxValid     : in  sl;
      -- Connection to ARP TX
      arpTxSenderMac : out MacAddrType;
      arpTxSenderIp  : out IpAddrType;
      arpTxTargetMac : out MacAddrType;
      arpTxTargetIp  : out IpAddrType;
      arpTxOp        : out slv(15 downto 0);
      arpTxReq       : out sl;
      arpTxAck       : in  sl    
   ); 
end ArpResponder;

architecture rtl of ArpResponder is

   type StateType is (IDLE_S, CHECK_IP_S, RESPOND_S, WAIT_S);
   
   type RegType is record
      state       : StateType;
      rxSenderMac : MacAddrType;
      rxSenderIp  : IpAddrType;
      rxTargetMac : MacAddrType;
      rxTargetIp  : IpAddrType;
      txSenderMac : MacAddrType;
      txSenderIp  : IpAddrType;
      txTargetMac : MacAddrType;
      txTargetIp  : IpAddrType;
      txOp        : slv(15 downto 0);
      txReq       : sl;
      matchedIp   : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state       => IDLE_S,
      rxSenderMac => MAC_ADDR_INIT_C,
      rxSenderIp  => IP_ADDR_INIT_C,
      rxTargetMac => MAC_ADDR_INIT_C,
      rxTargetIp  => IP_ADDR_INIT_C,
      txSenderMac => MAC_ADDR_INIT_C,
      txSenderIp  => IP_ADDR_INIT_C,
      txTargetMac => MAC_ADDR_INIT_C,
      txTargetIp  => IP_ADDR_INIT_C,
      txOp        => (others => '0'),
      txReq       => '0',
      matchedIp   => '0'
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

   comb : process(r,ethRst,macAddress,ipAddresses,
                  arpRxOp,arpRxSenderMac,arpRxSenderIp,arpRxTargetMac,
                  arpRxTargetIp,arpRxValid,arpTxAck) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      v.txReq := '0';
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            v.matchedIp := '0';
            if (arpRxValid = '1') then
               v.rxSenderMac := arpRxSenderMac;
               v.rxSenderIp  := arpRxSenderIp;
               v.rxTargetMac := arpRxTargetMac;
               v.rxTargetIp  := arpRxTargetIp;
               if (arpRxOp = ARP_OP_REQ_C) then
                  v.state := CHECK_IP_S;
               end if;
            end if;
         when CHECK_IP_S =>
            for ipNum in NUM_IP_G-1 downto 0 loop
               if (r.rxTargetIp = ipAddresses(ipNum)) then
                  v.matchedIp := '1';
               end if;
            end loop;
            if (v.matchedIp = '1') then
               v.state := RESPOND_S;
            else
               v.state := IDLE_S;
            end if;
         when RESPOND_S =>
            v.txReq       := '1';
            v.txSenderMac := macAddress;
            v.txSenderIp  := r.rxTargetIp;
            v.txTargetMac := r.rxSenderMac;
            v.txTargetIp  := r.rxSenderIp;
            v.txOp        := ARP_OP_RES_C;
            if (arpTxAck = '1') then
               v.state := WAIT_S;
            end if;
         when WAIT_S =>
            if (arpTxAck = '0') then
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      arpTxSenderMac <= r.txSenderMac;
      arpTxSenderIp  <= r.txSenderIp;
      arpTxTargetMac <= r.txTargetMac;
      arpTxTargetIp  <= r.txTargetIp;
      arpTxOp        <= r.txOp;
      arpTxReq       <= r.txReq;
      
      -- Assign variable to signal
      rin <= v;

   end process;

   seq : process (ethClk) is
   begin
      if (rising_edge(ethClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

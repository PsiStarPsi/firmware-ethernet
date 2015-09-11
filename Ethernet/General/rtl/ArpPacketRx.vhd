---------------------------------------------------------------------------------
-- Title         : ARP Packet RX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : ArpPacketRx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to Ethernet layer, reads incoming ARP packets
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity ArpPacketRx is 
   generic (
      GATE_DELAY_G   : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethRxClk       : in sl;
      ethRxRst       : in sl := '0';
      -- Incoming data from Ethernet frame
      ethRxSrcMac    : in  MacAddrType;
      ethRxDestMac   : in  MacAddrType;
      ethRxData      : in  slv( 7 downto 0);
      ethRxDataValid : in  sl;
      ethRxDataLast  : in  sl;
      -- Received data from ARP packet
      arpOp          : out slv(15 downto 0);
      arpSenderMac   : out MacAddrType;
      arpSenderIp    : out IpAddrType;
      arpTargetMac   : out MacAddrType;
      arpTargetIp    : out IpAddrType;
      arpValid       : out sl
   ); 

end ArpPacketRx;

-- Define architecture
architecture rtl of ArpPacketRx is

   type StateType is (IDLE_S, 
                      HTYPE_S, PTYPE_S, HLEN_S, PLEN_S, OPER_S, 
                      SHA_S, SPA_S, THA_S, TPA_S, DUMP_S);
   
   type RegType is record
      state        : StateType;
      rdCount      : slv(2 downto 0);
      senderMac    : MacAddrType;
      senderIp     : IpAddrType;
      targetMac    : MacAddrType;
      targetIp     : IpAddrType;
      op           : slv(15 downto 0);
      valid        : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state        => IDLE_S,
      rdCount      => (others => '0'),
      senderMac    => MAC_ADDR_INIT_C,
      senderIp     => IP_ADDR_INIT_C,
      targetMac    => MAC_ADDR_INIT_C,
      targetIp     => IP_ADDR_INIT_C,
      op           => (others => '0'),
      valid        => '0'
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

   comb : process(r,ethRxSrcMac,ethRxDestMac,ethRxData,
                  ethRxDataValid,ethRxDataLast,ethRxRst) is
      variable v : RegType;
   begin
      v := r;

      -- Resets for pulsed outputs
      v.valid := '0';
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            v.rdCount := (others => '0');
            if ethRxDataValid = '1' then
               if (ethRxData /= getByte(1,ARP_HTYPE_C)) then
                  v.state := DUMP_S;
               else
                  v.state := HTYPE_S;
               end if;
            end if;
         when HTYPE_S =>
            if ethRxDataValid = '1' then
               if (ethRxData /= getByte(0,ARP_HTYPE_C)) then
                  v.state := DUMP_S;
               else
                  v.state := PTYPE_S;
               end if;
            end if;
         when PTYPE_S =>
            if ethRxDataValid = '1' then
               if (ethRxData /= getByte(1-conv_integer(r.rdCount),ARP_PTYPE_C)) then
                  v.state := DUMP_S;
               else
                  v.rdCount := r.rdCount + 1;
                  if (r.rdCount = 1) then
                     v.rdCount := (others => '0');
                     v.state   := HLEN_S;
                  end if;
               end if;
            end if;
         when HLEN_S =>
            if ethRxDataValid = '1' then
               if (ethRxData /= ARP_HLEN_C) then
                  v.state := DUMP_S;
               else
                  v.state := PLEN_S;
               end if;
            end if;
         when PLEN_S =>
            if ethRxDataValid = '1' then
               if (ethRxData /= ARP_PLEN_C) then
                  v.state := DUMP_S;
               else
                  v.state := OPER_S;
               end if;
            end if;
         when OPER_S =>
            if ethRxDataValid = '1' then
               v.op((2-conv_integer(r.rdCount))*8-1 downto (1-conv_integer(r.rdCount))*8) := ethRxData;
               v.rdCount := r.rdCount + 1;
               if (r.rdCount = 1) then
                  v.rdCount := (others => '0');
                  v.state   := SHA_S;
               end if;
            end if;
         when SHA_S => 
            if ethRxDataValid = '1' then
               v.senderMac(5-conv_integer(r.rdCount)) := ethRxData;
               v.rdCount := r.rdCount + 1;
               if (r.rdCount = 5) then
                  v.rdCount := (others => '0');
                  v.state   := SPA_S;
               end if;
            end if;
         when SPA_S =>
            if ethRxDataValid = '1' then
               v.senderIp(3-conv_integer(r.rdCount)) := ethRxData;
               v.rdCount := r.rdCount + 1;
               if (r.rdCount = 3) then
                  v.rdCount := (others => '0');
                  v.state   := THA_S;
               end if;
            end if;
         when THA_S =>
            if ethRxDataValid = '1' then
               v.targetMac(5-conv_integer(r.rdCount)) := ethRxData;
               v.rdCount := r.rdCount + 1;
               if (r.rdCount = 5) then
                  v.rdCount := (others => '0');
                  v.state   := TPA_S;
               end if;
            end if;
         when TPA_S =>
            if ethRxDataValid = '1' then
               v.targetIp(3-conv_integer(r.rdCount)) := ethRxData;
               v.rdCount := r.rdCount + 1;
               if (r.rdCount = 3) then
                  v.rdCount := (others => '0');
                  v.valid   := '1';
                  v.state   := DUMP_S;
               end if;
            end if;         
         when DUMP_S =>
            if (ethRxDataLast = '1') then
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
      
      -- Should always return to idle if you see last out of place
      if (ethRxDataLast = '1' and r.state /= DUMP_S) then
         v.state := IDLE_S;
      end if;

      -- Reset logic
      if (ethRxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      arpSenderMac   <= r.senderMac;
      arpSenderIp    <= r.senderIp;
      arpTargetMac   <= r.targetMac;
      arpTargetIp    <= r.targetIp;
      arpValid       <= r.valid;
      arpOp          <= r.op;
      
      -- Assignment of combinatorial variable to signal
      rin <= v;

   end process;

   seq : process (ethRxClk) is
   begin
      if (rising_edge(ethRxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;


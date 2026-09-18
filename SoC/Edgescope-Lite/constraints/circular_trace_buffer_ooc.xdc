create_clock -name s_axi_aclk -period 10.000 [get_ports s_axi_aclk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports s_axi_aclk]

# s_axi_aresetn is a synchronous active-low reset in this design. Do not mark
# it false: its timing must be checked in the final system implementation.
# This OOC constraint intentionally measures registered internal paths only;
# interface input/output delays belong to the parent Block Design.

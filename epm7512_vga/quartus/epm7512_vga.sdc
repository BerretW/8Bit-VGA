# Timing constraints pro epm7512_vga
# Upravte periodu podle osazeného oscilátoru (25.000 MHz = 40.0 ns, 25.175 MHz = 39.722 ns)

create_clock -name clk_pix -period 40.0 [get_ports {clk_pix}]

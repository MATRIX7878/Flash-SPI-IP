if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work

vmap work rtl_work

vcom -work work [pwd]/*.vhd

vsim toplevel

add wave -recursive *

force clk 0, 1 13.5 -r 27
force RST 1 0, 0 50
force btn1 1 0
force btn2 1 0

view structure
view signals

run 50 us

view -undock wave
wave zoomfull
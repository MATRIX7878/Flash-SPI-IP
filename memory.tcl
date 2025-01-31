if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}

vlib rtl_work
vlib flashStates

vmap work rtl_work
vmap flashStates rtl_work

vcom -work flashStates [pwd]/flashStates.vhd
vcom -work work [pwd]/toplevel.vhd -suppress 1339
vcom -work work [pwd]/flash.vhd
vcom -work work [pwd]/UART.vhd

vsim toplevel

add wave -recursive *

force clk 0, 1 18.5 -r 37
force reset 1 0, 0 50

view structure
view signals

run 250 us

view -undock wave
wave zoomfull

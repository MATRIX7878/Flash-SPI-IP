if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}

vlib rtl_work
vlib flashStates

vmap work rtl_work
vmap flashStates rtl_work

vcom -work flashStates [pwd]/flashStates.vhd
vcom -work work [pwd]/flash.vhd
vcom -work work [pwd]/UARTTX.vhd
vcom -work work [pwd]/conv.vhd
vcom -work work [pwd]/top.vhd

vsim top

add wave -recursive *

force clk 0, 1 18.5 -r 37
force reset 1 0, 0 50
force MISO 'h0B15 1 ms

view structure
view signals

run 5 ms

view -undock wave
wave zoomfull

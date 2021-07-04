`ifndef _MEASURER_DEF_H_
`define _MEASURER_DEF_H_

///////////////////////////////////////////////////////////////////////////////
//Informacion del nodo
///////////////////////////////////////////////////////////////////////////////

`define NODE_ID            {8'd1}
`define NODE_VERSION_MAJOR {8'd1}
`define NODE_VERSION_MINOR {8'd1}

`define PRECISION {32'd125000000}
`define MEASUREMENT_SIZE {32'd9}

///////////////////////////////////////////////////////////////////////////////
//Comandos
///////////////////////////////////////////////////////////////////////////////

`define CMD_GET_ID              {8'h00}
`define CMD_GET_VERSION         {8'h01}
`define CMD_GET_PRECISION       {8'h02}
`define CMD_GET_MAC_ADDRESS     {8'h03}
`define CMD_GET_PACKET_SIZE     {8'h04}
`define CMD_GET_PACKET_INTERVAL {8'h05}
`define CMD_GET_PACKET_DST      {8'h06}
`define CMD_GET_CUSTOM_PACKET   {8'h07}
`define CMD_GET_BYTES_IN        {8'h08}
`define CMD_GET_BYTES_OUT       {8'h09}

`define CMD_SET_PACKET_SIZE     {8'h44}
`define CMD_SET_PACKET_INTERVAL {8'h45}
`define CMD_SET_PACKET_DST      {8'h46}
`define CMD_SET_CUSTOM_PACKET   {8'h47}

`define CMD_LOAD_CUSTOM_DATA    {8'h87}

`define CMD_MEASUREMENTS        {8'hC0}

`endif
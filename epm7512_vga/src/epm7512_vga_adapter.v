module epm7512_vga_adapter (
    input  wire        clk_pix,
    input  wire        reset_n,
    input  wire        test_mode,

    input  wire [15:0] cpu_a,
    inout  wire [7:0]  cpu_d,
    input  wire        memr_n,
    input  wire        memw_n,
    input  wire        ior_n,
    input  wire        iow_n,

    output wire        irq_n,

    output wire [2:0]  vga_r,
    output wire [2:0]  vga_g,
    output wire [2:0]  vga_b,
    output wire        hsync_n,
    output wire        vsync_n,

    output wire        eep_scl,
    inout  wire        eep_sda,

    output wire [16:0] sram_a,
    inout  wire [7:0]  sram_d,
    output wire        sram_ce_n,
    output wire        sram_oe_n,
    output wire        sram_we_n
);

    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = 10'd800;

    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = 10'd525;

    localparam REG_CTRL     = 5'h00;
    localparam REG_FG_COLOR = 5'h01;
    localparam REG_BG_COLOR = 5'h02;
    localparam REG_TXT_BASE_LO = 5'h03;
    localparam REG_TXT_BASE_HI = 5'h04;
    localparam REG_TXT_PTR_LO  = 5'h05;
    localparam REG_TXT_PTR_HI  = 5'h06;
    localparam REG_TXT_DATA    = 5'h07;
    localparam REG_FONT_BASE_LO = 5'h08;
    localparam REG_FONT_BASE_HI = 5'h09;
    localparam REG_FONT_PTR_LO  = 5'h0A;
    localparam REG_FONT_PTR_HI  = 5'h0B;
    localparam REG_FONT_DATA    = 5'h0C;
    localparam REG_STATUS       = 5'h0D;
    localparam REG_EE_I2C_CTRL  = 5'h0E;
    localparam REG_EE_I2C_STAT  = 5'h0F;

    localparam VID_REQ_NONE  = 2'd0;
    localparam VID_REQ_CHAR  = 2'd1;
    localparam VID_REQ_GLYPH = 2'd2;

    reg [9:0] h_count;
    reg [9:0] v_count;

    reg [7:0] ctrl_reg;
    reg [7:0] fg_reg;
    reg [7:0] bg_reg;

    reg [15:0] text_base;
    reg [15:0] text_ptr;
    reg [15:0] font_base;
    reg [15:0] font_ptr;

    reg [7:0] fetched_char;
    reg [7:0] current_glyph;
    reg [7:0] next_glyph;

    reg       eep_scl_r;
    reg       eep_sda_drive_low_r;

    reg memw_n_d;
    reg memr_n_d;

    reg [15:0] sram_addr_r;
    reg        sram_ce_n_r;
    reg        sram_oe_n_r;
    reg        sram_we_n_r;
    reg [7:0]  sram_d_out;
    reg        sram_d_oe;

    reg [7:0] cpu_read_data;

    reg [1:0] vid_req_kind;
    reg [15:0] vid_req_addr;

    wire [7:0] cpu_write_data;
    wire [7:0] sram_d_in;
    wire       eep_sda_in;

    wire visible;
    wire pixel_on;
    wire vblank;
    wire demo_mode;

    wire [2:0] demo_r;
    wire [2:0] demo_g;
    wire [2:0] demo_b;

    wire cpu_sel;
    wire cpu_wr_stb;
    wire cpu_rd_stb;
    wire cpu_wr_txt_data_stb;
    wire cpu_rd_txt_data_stb;
    wire cpu_wr_font_data_stb;
    wire cpu_rd_font_data_stb;

    wire [9:0] v_count_next;

    wire [4:0] char_row;
    wire [3:0] row_in_char;
    wire [6:0] char_col;

    wire [4:0] next_char_row;
    wire [3:0] next_row_in_char;

    wire [15:0] row80;
    wire [15:0] next_row80;

    wire [15:0] char_addr_next;
    wire [15:0] glyph_addr_fetched;
    wire [15:0] next_line_char0_addr;
    wire [15:0] next_line_glyph0_addr;

    wire [2:0] fg_r;
    wire [2:0] fg_g;
    wire [2:0] fg_b;
    wire [2:0] bg_r;
    wire [2:0] bg_g;
    wire [2:0] bg_b;

    assign cpu_write_data = cpu_d;
    assign sram_d_in = sram_d;
    assign eep_sda_in = eep_sda;

    assign visible = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign pixel_on = current_glyph[3'd7 - h_count[2:0]];
    assign vblank = (v_count >= V_VISIBLE);
    assign demo_mode = test_mode;

    assign cpu_sel = (cpu_a[15:8] == 8'hC0);

    assign cpu_wr_stb = cpu_sel && memw_n_d && !memw_n;
    assign cpu_rd_stb = cpu_sel && memr_n_d && !memr_n;

    assign cpu_wr_txt_data_stb = cpu_wr_stb && (cpu_a[4:0] == REG_TXT_DATA);
    assign cpu_rd_txt_data_stb = cpu_rd_stb && (cpu_a[4:0] == REG_TXT_DATA);
    assign cpu_wr_font_data_stb = cpu_wr_stb && (cpu_a[4:0] == REG_FONT_DATA);
    assign cpu_rd_font_data_stb = cpu_rd_stb && (cpu_a[4:0] == REG_FONT_DATA);

    assign char_row = v_count[8:4];
    assign row_in_char = v_count[3:0];
    assign char_col = h_count[9:3];

    assign v_count_next = (v_count == (V_TOTAL - 1)) ? 10'd0 : (v_count + 10'd1);

    assign next_char_row = v_count_next[8:4];
    assign next_row_in_char = v_count_next[3:0];

    assign row80 = ({11'd0, char_row} << 6) + ({11'd0, char_row} << 4);
    assign next_row80 = ({11'd0, next_char_row} << 6) + ({11'd0, next_char_row} << 4);

    assign char_addr_next = text_base + row80 + {9'd0, char_col} + 16'd1;
    assign glyph_addr_fetched = font_base + {4'b0000, fetched_char, 4'b0000} + {12'd0, row_in_char};
    assign next_line_char0_addr = text_base + next_row80;
    assign next_line_glyph0_addr = font_base + {4'b0000, fetched_char, 4'b0000} + {12'd0, next_row_in_char};

    assign fg_r = fg_reg[2:0];
    assign fg_g = fg_reg[5:3];
    assign fg_b = {fg_reg[7:6], fg_reg[7]};

    assign bg_r = bg_reg[2:0];
    assign bg_g = bg_reg[5:3];
    assign bg_b = {bg_reg[7:6], bg_reg[7]};

    assign demo_r = {h_count[7], v_count[6], h_count[4] ^ v_count[4]};
    assign demo_g = {v_count[7], h_count[6], h_count[5] ^ v_count[5]};
    assign demo_b = {h_count[8] ^ v_count[8], h_count[3], v_count[3]};

    assign vga_r = !visible ? 3'b000 : (demo_mode ? demo_r : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_r : bg_r)));
    assign vga_g = !visible ? 3'b000 : (demo_mode ? demo_g : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_g : bg_g)));
    assign vga_b = !visible ? 3'b000 : (demo_mode ? demo_b : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_b : bg_b)));

    assign hsync_n = ~((h_count >= (H_VISIBLE + H_FRONT)) && (h_count < (H_VISIBLE + H_FRONT + H_SYNC)));
    assign vsync_n = ~((v_count >= (V_VISIBLE + V_FRONT)) && (v_count < (V_VISIBLE + V_FRONT + V_SYNC)));

    assign eep_scl = eep_scl_r;
    assign eep_sda = eep_sda_drive_low_r ? 1'b0 : 1'bZ;

    assign cpu_d = (cpu_sel && !memr_n) ? cpu_read_data : 8'hZZ;

    assign sram_a    = {1'b0, sram_addr_r};
    assign sram_ce_n = sram_ce_n_r;
    assign sram_oe_n = sram_oe_n_r;
    assign sram_we_n = sram_we_n_r;
    assign sram_d    = sram_d_oe ? sram_d_out : 8'hZZ;

    assign irq_n = 1'b1;

    always @(*) begin
        cpu_read_data = 8'hFF;

        case (cpu_a[4:0])
            REG_CTRL:     cpu_read_data = ctrl_reg;
            REG_FG_COLOR: cpu_read_data = fg_reg;
            REG_BG_COLOR: cpu_read_data = bg_reg;
            REG_TXT_BASE_LO:  cpu_read_data = text_base[7:0];
            REG_TXT_BASE_HI:  cpu_read_data = text_base[15:8];
            REG_TXT_PTR_LO:   cpu_read_data = text_ptr[7:0];
            REG_TXT_PTR_HI:   cpu_read_data = text_ptr[15:8];
            REG_TXT_DATA:     cpu_read_data = sram_d_in;
            REG_FONT_BASE_LO: cpu_read_data = font_base[7:0];
            REG_FONT_BASE_HI: cpu_read_data = font_base[15:8];
            REG_FONT_PTR_LO:  cpu_read_data = font_ptr[7:0];
            REG_FONT_PTR_HI:  cpu_read_data = font_ptr[15:8];
            REG_FONT_DATA:    cpu_read_data = sram_d_in;
            REG_STATUS:       cpu_read_data = {7'b0000000, vblank};
            REG_EE_I2C_CTRL:  cpu_read_data = {6'b000000, eep_sda_drive_low_r, eep_scl_r};
            REG_EE_I2C_STAT:  cpu_read_data = {5'b00000, eep_sda_drive_low_r, eep_scl_r, eep_sda_in};
            default:      cpu_read_data = 8'hFF;
        endcase
    end

    always @(*) begin
        vid_req_kind = VID_REQ_NONE;
        vid_req_addr = 16'h0000;

        if (!demo_mode && visible) begin
            if ((h_count[2:0] == 3'd5) && (char_col < 7'd79)) begin
                vid_req_kind = VID_REQ_CHAR;
                vid_req_addr = char_addr_next;
            end else if ((h_count[2:0] == 3'd6) && (char_col < 7'd79)) begin
                vid_req_kind = VID_REQ_GLYPH;
                vid_req_addr = glyph_addr_fetched;
            end
        end else if (!demo_mode && (h_count == (H_TOTAL - 3))) begin
            vid_req_kind = VID_REQ_CHAR;
            vid_req_addr = next_line_char0_addr;
        end else if (!demo_mode && (h_count == (H_TOTAL - 2))) begin
            vid_req_kind = VID_REQ_GLYPH;
            vid_req_addr = next_line_glyph0_addr;
        end

        sram_addr_r = vid_req_addr;
        sram_ce_n_r = 1'b1;
        sram_oe_n_r = 1'b1;
        sram_we_n_r = 1'b1;
        sram_d_out  = cpu_write_data;
        sram_d_oe   = 1'b0;

        if (cpu_sel && (cpu_a[4:0] == REG_TXT_DATA) && !memw_n) begin
            sram_addr_r = text_ptr;
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b1;
            sram_we_n_r = 1'b0;
            sram_d_oe   = 1'b1;
        end else if (cpu_sel && (cpu_a[4:0] == REG_TXT_DATA) && !memr_n) begin
            sram_addr_r = text_ptr;
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b0;
            sram_we_n_r = 1'b1;
        end else if (cpu_sel && (cpu_a[4:0] == REG_FONT_DATA) && !memw_n) begin
            sram_addr_r = font_ptr;
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b1;
            sram_we_n_r = 1'b0;
            sram_d_oe   = 1'b1;
        end else if (cpu_sel && (cpu_a[4:0] == REG_FONT_DATA) && !memr_n) begin
            sram_addr_r = font_ptr;
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b0;
            sram_we_n_r = 1'b1;
        end else if (vid_req_kind != VID_REQ_NONE) begin
            sram_addr_r = vid_req_addr;
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b0;
            sram_we_n_r = 1'b1;
        end
    end

    always @(posedge clk_pix or negedge reset_n) begin
        if (!reset_n) begin
            h_count   <= 10'd0;
            v_count   <= 10'd0;

            ctrl_reg  <= 8'h00;
            fg_reg    <= 8'b11111111;
            bg_reg    <= 8'b00000000;

            text_base <= 16'h0000;
            text_ptr  <= 16'h0000;
            font_base <= 16'h1000;
            font_ptr  <= 16'h1000;

            fetched_char  <= 8'h20;
            current_glyph <= 8'h00;
            next_glyph    <= 8'h00;

            eep_scl_r <= 1'b1;
            eep_sda_drive_low_r <= 1'b0;

            memw_n_d  <= 1'b1;
            memr_n_d  <= 1'b1;
        end else begin
            memw_n_d <= memw_n;
            memr_n_d <= memr_n;

            if (vid_req_kind == VID_REQ_CHAR) begin
                fetched_char <= sram_d_in;
            end

            if (vid_req_kind == VID_REQ_GLYPH) begin
                next_glyph <= sram_d_in;
            end

            if (h_count[2:0] == 3'd7) begin
                current_glyph <= next_glyph;
            end

            if (h_count == (H_TOTAL - 1)) begin
                h_count <= 10'd0;

                if (v_count == (V_TOTAL - 1)) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 10'd1;
                end
            end else begin
                h_count <= h_count + 10'd1;
            end

            if (cpu_wr_stb) begin
                case (cpu_a[4:0])
                    REG_CTRL:          ctrl_reg <= cpu_write_data;
                    REG_FG_COLOR:      fg_reg <= cpu_write_data;
                    REG_BG_COLOR:      bg_reg <= cpu_write_data;
                    REG_TXT_BASE_LO:   text_base[7:0] <= cpu_write_data;
                    REG_TXT_BASE_HI:   text_base[15:8] <= cpu_write_data;
                    REG_TXT_PTR_LO:    text_ptr[7:0] <= cpu_write_data;
                    REG_TXT_PTR_HI:    text_ptr[15:8] <= cpu_write_data;
                    REG_FONT_BASE_LO:  font_base[7:0] <= cpu_write_data;
                    REG_FONT_BASE_HI:  font_base[15:8] <= cpu_write_data;
                    REG_FONT_PTR_LO:   font_ptr[7:0] <= cpu_write_data;
                    REG_FONT_PTR_HI:   font_ptr[15:8] <= cpu_write_data;
                    REG_EE_I2C_CTRL: begin
                        eep_scl_r <= cpu_write_data[0];
                        eep_sda_drive_low_r <= cpu_write_data[1];
                    end
                    default: ;
                endcase
            end

            if (cpu_wr_txt_data_stb || cpu_rd_txt_data_stb) begin
                text_ptr <= text_ptr + 16'd1;
            end

            if (cpu_wr_font_data_stb || cpu_rd_font_data_stb) begin
                font_ptr <= font_ptr + 16'd1;
            end
        end
    end

endmodule

module epm7512_vga_adapter_lite (
    input  wire        clk_pix,
    input  wire        reset_n,
    input  wire        test_mode,

    input  wire [15:0] cpu_a,
    inout  wire [7:0]  cpu_d,
    input  wire        rw,

    output wire        irq_n,

    output wire [2:0]  vga_r,
    output wire [2:0]  vga_g,
    output wire [2:0]  vga_b,
    output wire        hsync_n,
    output wire        vsync_n,

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

    // Registers (minimální sada)
    localparam REG_CTRL     = 5'h00;
    localparam REG_TXT_PTR_LO  = 5'h01;
    localparam REG_TXT_PTR_HI  = 5'h02;
    localparam REG_TXT_DATA    = 5'h03;
    localparam REG_FONT_PTR_LO = 5'h04;
    localparam REG_FONT_PTR_HI = 5'h05;
    localparam REG_FONT_DATA   = 5'h06;
    localparam REG_STATUS      = 5'h07;
    localparam REG_HW_VERSION  = 5'h08;  // HW verze: 0x01 = lite adapter
    localparam REG_HW_ID       = 5'h09;  // HW ID: 0xA3 = "VGA adapter"
    localparam REG_FG_COLOR    = 5'h0A;  // Foreground color (3:3:2 RGB)
    localparam REG_BG_COLOR    = 5'h0B;  // Background color (3:3:2 RGB)
    
    // Hardware version constants
    localparam HW_VERSION = 8'h01;  // Version 1.0
    localparam HW_ID      = 8'hA3;  // Identifier: lite adapter VGA

    reg [9:0] h_count;
    reg [9:0] v_count;

    reg [7:0] ctrl_reg;
    reg [7:0] fg_color_reg;
    reg [7:0] bg_color_reg;
    reg [15:0] text_ptr;
    reg [15:0] font_ptr;

    reg [7:0] fetched_char;
    reg [7:0] fetched_glyph;

    reg rw_s1, rw_s2, rw_s3;  // 3-stage sync: metastability + data settling

    reg [16:0] sram_addr_r;
    reg        sram_ce_n_r;
    reg        sram_oe_n_r;
    reg        sram_we_n_r;
    reg [7:0]  sram_d_out;
    reg        sram_d_oe;

    reg [7:0] cpu_read_data;

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

    wire [4:0] char_row;
    wire [3:0] row_in_char;
    wire [6:0] char_col;
    wire [15:0] char_addr;
    wire [15:0] glyph_addr;
    
    wire [2:0] fg_r, fg_g, fg_b;
    wire [2:0] bg_r, bg_g, bg_b;

    assign visible = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign pixel_on = fetched_glyph[3'd7 - h_count[2:0]];
    assign vblank = (v_count >= V_VISIBLE);
    assign demo_mode = test_mode;

    assign cpu_sel    = (cpu_a[15:8] == 8'hC0);
    // RW=1: CPU cte, RW=0: CPU pise
    // Write strobe: padajici hrana RW (rw_s3 byl 1, rw_s2 je 0), data ustala >= 120 ns
    assign cpu_wr_stb = cpu_sel && rw_s3 && !rw_s2;
    assign cpu_rd_stb = cpu_sel && !rw_s3 && rw_s2;  // nastupna hrana RW = konec zapisu

    // Compute character position (80×60 grid)
    assign char_row = v_count[8:4];
    assign row_in_char = v_count[3:0];
    assign char_col = h_count[9:3];

    // Text base = 0x0000, Font base = 0x1000
    // char_addr = row*80 + col = (row << 6) + (row << 4) + col
    assign char_addr = ((char_row << 6) + (char_row << 4)) + {9'd0, char_col};
    assign glyph_addr = 16'h1000 + {4'b0000, fetched_char, 4'b0000} + {12'd0, row_in_char};

    // Color format: [7:5]=R, [4:2]=G, [1:0]=B (3:3:2 RGB)
    assign fg_r = fg_color_reg[7:5];
    assign fg_g = fg_color_reg[4:2];
    assign fg_b = {fg_color_reg[1:0], fg_color_reg[1]};  // Replicate 2-bit B to 3-bit
    
    assign bg_r = bg_color_reg[7:5];
    assign bg_g = bg_color_reg[4:2];
    assign bg_b = {bg_color_reg[1:0], bg_color_reg[1]};  // Replicate 2-bit B to 3-bit

    assign demo_r = {h_count[7], v_count[6], h_count[4] ^ v_count[4]};
    assign demo_g = {v_count[7], h_count[6], h_count[5] ^ v_count[5]};
    assign demo_b = {h_count[8] ^ v_count[8], h_count[3], v_count[3]};

    assign vga_r = !visible ? 3'b000 : (demo_mode ? demo_r : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_r : bg_r)));
    assign vga_g = !visible ? 3'b000 : (demo_mode ? demo_g : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_g : bg_g)));
    assign vga_b = !visible ? 3'b000 : (demo_mode ? demo_b : (!ctrl_reg[0] ? 3'b000 : (pixel_on ? fg_b : bg_b)));

    assign hsync_n = ~((h_count >= (H_VISIBLE + H_FRONT)) && (h_count < (H_VISIBLE + H_FRONT + H_SYNC)));
    assign vsync_n = ~((v_count >= (V_VISIBLE + V_FRONT)) && (v_count < (V_VISIBLE + V_FRONT + V_SYNC)));

    assign cpu_d = (cpu_sel && rw_s2) ? cpu_read_data : 8'hZZ;

    assign sram_a    = sram_addr_r;
    assign sram_ce_n = sram_ce_n_r;
    assign sram_oe_n = sram_oe_n_r;
    assign sram_we_n = sram_we_n_r;
    assign sram_d    = sram_d_oe ? sram_d_out : 8'hZZ;

    assign irq_n = 1'b1;

    always @(*) begin
        cpu_read_data = 8'hFF;
        case (cpu_a[4:0])
            REG_CTRL:          cpu_read_data = ctrl_reg;
            REG_TXT_PTR_LO:    cpu_read_data = text_ptr[7:0];
            REG_TXT_PTR_HI:    cpu_read_data = text_ptr[15:8];
            REG_FONT_PTR_LO:   cpu_read_data = font_ptr[7:0];
            REG_FONT_PTR_HI:   cpu_read_data = font_ptr[15:8];
            REG_STATUS:        cpu_read_data = {7'b0000000, vblank};
            REG_HW_VERSION:    cpu_read_data = HW_VERSION;  // Read-only
            REG_HW_ID:         cpu_read_data = HW_ID;       // Read-only
            REG_FG_COLOR:      cpu_read_data = fg_color_reg;
            REG_BG_COLOR:      cpu_read_data = bg_color_reg;
            default:           cpu_read_data = 8'hFF;
        endcase
    end

    always @(*) begin
        // Default: video fetch (read char from text_base)
        sram_addr_r = {1'b0, char_addr};
        sram_ce_n_r = 1'b0;
        sram_oe_n_r = 1'b0;
        sram_we_n_r = 1'b1;
        sram_d_out  = 8'h00;
        sram_d_oe   = 1'b0;

        // CPU access overrides video fetch
        if (cpu_sel && !rw_s2) begin  // RW=0: CPU pise
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b1;
            sram_we_n_r = 1'b0;
            sram_d_out  = cpu_d;
            sram_d_oe   = 1'b1;

            case (cpu_a[4:0])
                REG_TXT_DATA:   sram_addr_r = {1'b0, text_ptr};
                REG_FONT_DATA:  sram_addr_r = {1'b0, font_ptr};
                default:        sram_ce_n_r = 1'b1;
            endcase
        end else if (cpu_sel && rw_s2) begin  // RW=1: CPU cte
            sram_ce_n_r = 1'b0;
            sram_oe_n_r = 1'b0;
            sram_we_n_r = 1'b1;

            case (cpu_a[4:0])
                REG_TXT_DATA:   sram_addr_r = {1'b0, text_ptr};
                REG_FONT_DATA:  sram_addr_r = {1'b0, font_ptr};
                default:        sram_ce_n_r = 1'b1;
            endcase
        end else if (h_count[2:0] == 3'd5) begin
            // At pixel 5: fetch character
            sram_addr_r = {1'b0, char_addr};
        end else if (h_count[2:0] == 3'd6) begin
            // At pixel 6: fetch glyph
            sram_addr_r = {1'b0, glyph_addr};
        end
    end

    always @(posedge clk_pix or negedge reset_n) begin
        if (!reset_n) begin
            h_count   <= 10'd0;
            v_count   <= 10'd0;
            ctrl_reg  <= 8'h00;
            fg_color_reg <= 8'hFF;  // White text
            bg_color_reg <= 8'h00;  // Black background
            text_ptr  <= 16'h0000;
            font_ptr  <= 16'h0000;
            fetched_char  <= 8'h20;
            fetched_glyph <= 8'h00;
            rw_s1 <= 1'b1;
            rw_s2 <= 1'b1;
            rw_s3 <= 1'b1;
        end else begin
            rw_s1 <= rw;
            rw_s2 <= rw_s1;
            rw_s3 <= rw_s2;

            // Fetch character and glyph from SRAM during video
            if (h_count[2:0] == 3'd5) begin
                fetched_char <= sram_d;
            end
            if (h_count[2:0] == 3'd6) begin
                fetched_glyph <= sram_d;
            end

            // Horizontal/vertical timing
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

            // CPU write to registers
            if (cpu_wr_stb) begin
                case (cpu_a[4:0])
                    REG_CTRL:          ctrl_reg <= cpu_d;
                    REG_FG_COLOR:      fg_color_reg <= cpu_d;
                    REG_BG_COLOR:      bg_color_reg <= cpu_d;
                    REG_TXT_PTR_LO:    text_ptr[7:0] <= cpu_d;
                    REG_TXT_PTR_HI:    text_ptr[15:8] <= cpu_d;
                    REG_FONT_PTR_LO:   font_ptr[7:0] <= cpu_d;
                    REG_FONT_PTR_HI:   font_ptr[15:8] <= cpu_d;
                    default: ;
                endcase
            end

            // Auto-increment pointers on text/font data access
            if (cpu_wr_stb && (cpu_a[4:0] == REG_TXT_DATA)) begin
                text_ptr <= text_ptr + 16'd1;
            end
            if (cpu_rd_stb && (cpu_a[4:0] == REG_TXT_DATA)) begin
                text_ptr <= text_ptr + 16'd1;
            end
            if (cpu_wr_stb && (cpu_a[4:0] == REG_FONT_DATA)) begin
                font_ptr <= font_ptr + 16'd1;
            end
            if (cpu_rd_stb && (cpu_a[4:0] == REG_FONT_DATA)) begin
                font_ptr <= font_ptr + 16'd1;
            end
        end
    end

endmodule

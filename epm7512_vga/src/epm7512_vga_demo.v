module epm7512_vga_demo (
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
    output wire [9:0]  diag_led,

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

    localparam REG_DEMO_CTRL = 5'h00;

    reg [9:0] h_count;
    reg [9:0] v_count;
    reg       rw_s1, rw_s2, rw_s3;  // 3-stage sync: metastability + data settling
    reg [7:0] demo_ctrl_reg;

    reg [7:0] cpu_read_data;

    wire visible;
    wire demo_enable;

    wire [2:0] demo_r;
    wire [2:0] demo_g;
    wire [2:0] demo_b;

    wire cpu_sel;
    wire cpu_wr_stb;
    wire cpu_rd_sel;

    assign visible = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign demo_enable = test_mode | demo_ctrl_reg[0];

    assign cpu_sel    = (cpu_a[15:8] == 8'hC0);
    // Edge detect na synchronizovaném RW: rw_s3 byl 1, rw_s2 je 0 → padající hrana
    // Data cpu_d jsou ustálena >= 3 × 40 ns = 120 ns po poklesu RW
    assign cpu_wr_stb = cpu_sel && rw_s3 && !rw_s2;
    assign cpu_rd_sel = cpu_sel && rw_s2;

    assign demo_r = {h_count[7], v_count[6], h_count[4] ^ v_count[4]};
    assign demo_g = {v_count[7], h_count[6], h_count[5] ^ v_count[5]};
    assign demo_b = {h_count[8] ^ v_count[8], h_count[3], v_count[3]};

    assign vga_r = (!visible || !demo_enable) ? 3'b000 : demo_r;
    assign vga_g = (!visible || !demo_enable) ? 3'b000 : demo_g;
    assign vga_b = (!visible || !demo_enable) ? 3'b000 : demo_b;

    assign hsync_n = ~((h_count >= (H_VISIBLE + H_FRONT)) && (h_count < (H_VISIBLE + H_FRONT + H_SYNC)));
    assign vsync_n = ~((v_count >= (V_VISIBLE + V_FRONT)) && (v_count < (V_VISIBLE + V_FRONT + V_SYNC)));

    always @(*) begin
        cpu_read_data = 8'hFF;
        case (cpu_a[4:0])
            REG_DEMO_CTRL: cpu_read_data = demo_ctrl_reg;
            default:       cpu_read_data = 8'hFF;
        endcase
    end

    always @(posedge clk_pix or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
            rw_s1 <= 1'b1;
            rw_s2 <= 1'b1;
            rw_s3 <= 1'b1;
            demo_ctrl_reg <= 8'h00;
        end else begin
            rw_s1 <= rw;
            rw_s2 <= rw_s1;
            rw_s3 <= rw_s2;

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
                    REG_DEMO_CTRL: demo_ctrl_reg <= cpu_d;
                    default: ;
                endcase
            end
        end
    end

    assign cpu_d = cpu_rd_sel ? cpu_read_data : 8'hZZ;

    assign sram_a    = 17'h00000;
    assign sram_ce_n = 1'b1;
    assign sram_oe_n = 1'b1;
    assign sram_we_n = 1'b1;
    assign sram_d    = 8'hZZ;

    assign eep_scl = 1'b1;
    assign eep_sda = 1'bZ;

    assign diag_led[0] = demo_ctrl_reg[0];
    assign diag_led[1] = demo_ctrl_reg[1];
    assign diag_led[2] = demo_ctrl_reg[2];
    assign diag_led[3] = demo_ctrl_reg[3];
    assign diag_led[4] = demo_ctrl_reg[4];
    assign diag_led[5] = demo_ctrl_reg[5];
    assign diag_led[6] = demo_ctrl_reg[6];
    assign diag_led[7] = demo_ctrl_reg[7];
    assign diag_led[8] = demo_ctrl_reg[0];
    assign diag_led[9] = demo_ctrl_reg[1];

    assign irq_n = 1'b1;

    wire _unused_ok;
    assign _unused_ok = &{1'b0};

endmodule

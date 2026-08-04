`timescale 1ns / 1ps

module custom_vending_top(

    input clk,

    input btnU,      // OPEN
    input btnD,      // CLOSE

    input [15:0] sw,

    output [15:0] led,

    output servo_out

);

wire flag_cplt_DONE;

wire flag_cplt_SERVO;
wire flag_cplt_CHANGE;

/////////////////////////////////////////////////////////
// LED Animation
/////////////////////////////////////////////////////////

led_animation_ctrl U_LED(

    .clk(clk),
    .reset_p(sw[15]),

    .flag_DONE(btnU),

    .led(led),

    .flag_cplt_DONE(flag_cplt_DONE)

);

/////////////////////////////////////////////////////////
// Servo PWM
/////////////////////////////////////////////////////////

servo_pwm U_SERVO(

    .clk(clk),
    .reset_p(sw[15]),

    .flag_SERVO(btnU),
    .flag_CHANGE(btnD),

    .servo_out(servo_out),

    .flag_cplt_SERVO(flag_cplt_SERVO),
    .flag_cplt_CHANGE(flag_cplt_CHANGE)

);

endmodule
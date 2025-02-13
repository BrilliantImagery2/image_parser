//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const print = std.debug.print;

const JpgError = @import("errors.zig").JpgError;
const Marker = @import("constants.zig").Marker;

pub const JpgReader = struct {
    data: []const u8,
    position: usize = 0,

    pub fn init(data: []const u8) JpgReader {
        return .{ .data = data };
    }

    pub inline fn readInt(self: *JpgReader, comptime T: type) T {
        const value = self.peekInt(T);
        self.position += @sizeOf(T);
        return value;
    }

    pub inline fn peekInt(self: *JpgReader, comptime T: type) T {
        if (T == u8) return self.data[self.position];
        const size = @sizeOf(T);
        var value: T = 0;
        if (!(self.position + size < self.data.len)) {
            return 0;
        }
        for (self.data[self.position .. self.position + size][0..size]) |b| {
            value = value << 8 | b;
        }
        return value;
    }

    pub inline fn hasNext(self: JpgReader) bool {
        return self.position - 1 < self.data.len;
    }

    pub inline fn has2Next(self: JpgReader) bool {
        if (self.position > 10) {
            return self.position - 10 < self.data.len;
        }
        return true;
    }

    pub inline fn skip(self: *JpgReader) void {
        self.position += 1;
    }
};

pub fn main() !void {
    if (std.os.argv.len == 1) {
        std.debug.print("{s}\n", .{"don't forget to include a path."});
        return;
    }
    const file_path = std.mem.span(std.os.argv[1]);
    const file = open_file(file_path);

    var reader = JpgReader.init(file);
    try is_jpg(&reader);

    while (reader.hasNext()) {
        switch (reader.peekInt(u16)) {
            0...0xFF01, 0xFFFF => {
                reader.skip();
            },
            @intFromEnum(Marker.SOF0), @intFromEnum(Marker.SOF3) => {
                parseFrameHeader(&reader);
            },
            else => {
                reader.skip();
            },
        }
    }
}

fn parseFrameHeader(reader: *JpgReader) void {
    print("Frame Header, B.2.2, p.35{s}\n", .{""});
    const marker = reader.readInt(u16);
    switch (marker) {
        @intFromEnum(Marker.SOF0) => {
            print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "SOF0", "u16", marker, marker });
            print("    Lossy Jpg encoding{s}\n", .{""});
        },
        @intFromEnum(Marker.SOF3) => {
            print("  {s: <32}  {s: >4},  {s: >3},  0x{X},  {d: >5}\n", .{ "Marker:", "SOF3", "u16", marker, marker });
            print("    Lossless Jpg encoding{s}\n", .{""});
        },
        else => {
            print("  Marker not implimented\n{s}", .{""});
        },
    }
    const l_f = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Frame header length:", "Lf", "u16", l_f, l_f });
    const p_ = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Sample precision:", "P", "u8", p_, p_ });
    const y_ = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Number of lines:", "Y", "u16", y_, y_ });
    const x_ = reader.readInt(u16);
    print("  {s: <32}  {s: >4},  {s: >3},  0x{X:0>4},  {d: >5}\n", .{ "Numb of samples per line:", "X", "u16", x_, x_ });
    const n_f = reader.readInt(u8);
    print("  {s: <32}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Numb of image comps in frame:", "Nf", "u8", n_f, n_f });
    print("\n{s}", .{""});
    for (0..n_f) |_| {
        const c_i = reader.readInt(u8);
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Component identifier:", "Ci", "u8", c_i, c_i });
        const h_i_v_i = reader.readInt(u8);
        const h_i = h_i_v_i >> 4;
        const v_i = h_i_v_i & 0x0F;
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Horizontal sample factor:", "Hi", "u4", h_i, h_i });
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Vertical sample factor:", "Vi", "u4", v_i, v_i });
        const t_qi = reader.readInt(u8);
        print("    {s: <30}  {s: >4},  {s: >3},    0x{X:0>2},  {d: >5}\n", .{ "Quant table dest selector:", "Tqi", "u4", t_qi, t_qi });
        print("\n{s}", .{""});
    }
}

fn is_jpg(reader: *JpgReader) JpgError!void {
    if (reader.readInt(u16) != @intFromEnum(Marker.SOI)) {
        return JpgError.InvalidSOI;
    }
}

fn open_file(file_path: []const u8) []u8 {
    const allocator = std.heap.page_allocator;

    // Change the file path to the binary file you want to read.
    //const file_path = "tests/F-18.ljpg";

    // Open the file.
    var file = std.fs.cwd().openFile(file_path, .{}) catch unreachable;
    defer file.close();

    // Get the file size.
    const file_size = file.getEndPos() catch unreachable;

    // Allocate a buffer for the file contents.
    const buffer = allocator.alloc(u8, file_size) catch unreachable;
    // defer allocator.free(buffer);

    // Read the entire file into the buffer.
    const read_bytes = file.readAll(buffer) catch unreachable;
    if (read_bytes != file_size) {
        //return error.ReadError; // Custom error for incomplete read.
        unreachable;
    }

    return buffer[0..read_bytes];
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const global = struct {
        fn testOne(input: []const u8) anyerror!void {
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(global.testOne, .{});
}

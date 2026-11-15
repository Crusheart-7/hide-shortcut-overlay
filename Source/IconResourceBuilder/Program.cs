using System.Text;

if (args.Length != 1) throw new ArgumentException("Pass the output .res path.");
using var stream = File.Create(args[0]);
using var writer = new BinaryWriter(stream, Encoding.Unicode);

// Standard null resource header.
WriteResource(0, 0, Array.Empty<byte>());

int[] sizes = [16, 24, 32, 48, 64, 256];
var images = sizes.Select(MakeDib).ToArray();
for (ushort i = 0; i < sizes.Length; i++)
    WriteResource(3, (ushort)(i + 1), images[i]); // RT_ICON

using var groupStream = new MemoryStream();
using (var group = new BinaryWriter(groupStream, Encoding.Unicode, leaveOpen: true))
{
    group.Write((ushort)0);
    group.Write((ushort)1);
    group.Write((ushort)sizes.Length);
    for (ushort i = 0; i < sizes.Length; i++)
    {
        group.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
        group.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
        group.Write((byte)0);
        group.Write((byte)0);
        group.Write((ushort)1);
        group.Write((ushort)32);
        group.Write((uint)images[i].Length);
        group.Write((ushort)(i + 1));
    }
}
var groupData = groupStream.ToArray();
for (ushort id = 1; id <= 198; id++)
    WriteResource(14, id, groupData); // RT_GROUP_ICON; index 197 is resource ID 198.

void WriteResource(ushort type, ushort name, byte[] data)
{
    writer.Write((uint)data.Length);
    writer.Write((uint)32);
    writer.Write((ushort)0xffff);
    writer.Write(type);
    writer.Write((ushort)0xffff);
    writer.Write(name);
    writer.Write((uint)0);  // DataVersion
    writer.Write((ushort)0x1030); // moveable, pure, discardable
    writer.Write((ushort)0x0409); // neutral English resource language
    writer.Write((uint)0);
    writer.Write((uint)0);
    writer.Write(data);
    while ((stream.Position & 3) != 0) writer.Write((byte)0);
}

static byte[] MakeDib(int size)
{
    int maskStride = ((size + 31) / 32) * 4;
    using var mem = new MemoryStream();
    using var b = new BinaryWriter(mem);
    b.Write((uint)40);                 // BITMAPINFOHEADER
    b.Write(size);
    b.Write(size * 2);                // XOR + AND bitmap heights
    b.Write((ushort)1);
    b.Write((ushort)32);
    b.Write((uint)0);                 // BI_RGB
    b.Write((uint)(size * size * 4 + size * maskStride));
    b.Write(0);
    b.Write(0);
    b.Write((uint)0);
    b.Write((uint)0);
    for (int p = 0; p < size * size; p++)
        b.Write((uint)0x01000000);    // BGRA: black, alpha = 1 / 255
    b.Write(new byte[size * maskStride]); // no AND mask; alpha controls transparency
    return mem.ToArray();
}

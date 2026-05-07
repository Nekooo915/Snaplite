import AppKit

enum Clipboard {
    /// Copy a PNG file to the system clipboard as a real image (so the
    /// user can paste it into Preview, iMessage, Slack, … as a picture
    /// rather than a file reference). We attach both the PNG bytes and a
    /// derived NSImage to maximise paste-target compatibility.
    static func copyImage(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let image = NSImage(data: data) else { return false }

        let pb = NSPasteboard.general
        pb.clearContents()
        var ok = pb.setData(data, forType: .png)
        ok = pb.writeObjects([image]) || ok
        return ok
    }
}

class BikeTool < Formula
  desc "CLI for reading and safely editing Bike.app .bike outline files"
  homepage "https://github.com/rbarooah/bike-tool"
  url "https://github.com/rbarooah/bike-tool/archive/bcb169c54415018917fa9b903a0a4edae875bcbd.tar.gz"
  version "0.1.0"
  sha256 "ecdbe2c9b9988c5ebbd1d16f416b9af7d6be30bbeecff8e7b7c04a10059af674"
  license "MIT"

  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/bike-tool"
  end

  test do
    bike_file = testpath/"sample.bike"
    bike_file.write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <meta charset="utf-8"/>
        </head>
        <body>
          <ul>
            <li id="abc123" data-type="task">
              <p>Smoke test task</p>
            </li>
          </ul>
        </body>
      </html>
    XML

    output = shell_output("#{bin}/bike-tool validate #{bike_file}")
    assert_match "is valid Bike XML", output
  end
end

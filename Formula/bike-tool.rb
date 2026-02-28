class BikeTool < Formula
  desc "CLI for reading and safely editing Bike.app .bike outline files"
  homepage "https://github.com/rbarooah/bike-tool"
  url "https://github.com/rbarooah/bike-tool/archive/9930963648878ba73b0feec4ce17fa9539b8fd9c.tar.gz"
  version "0.2.1"
  sha256 "5222da25375cd4c8974deaa188c1d5daeff06db825247e59cb2300738c433cec"
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

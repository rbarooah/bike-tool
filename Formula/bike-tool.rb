class BikeTool < Formula
  desc "CLI for reading and safely editing Bike.app .bike outline files"
  homepage "https://github.com/rbarooah/bike-tool"
  url "https://github.com/rbarooah/bike-tool/archive/e2d88d2a76f970f3add1a88e6f0f079528e36a27.tar.gz"
  version "0.2.3"
  sha256 "08688231bafb2f978a20267e6af7edfc09a5dbe83dd5ed92151f8931b16d1645"
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

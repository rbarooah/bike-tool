class BikeTool < Formula
  desc "CLI for reading and safely editing Bike.app .bike outline files"
  homepage "https://github.com/rbarooah/bike-tool"
  url "https://github.com/rbarooah/bike-tool/archive/adeb6b1fdebb2047dc8edc41a065389f6040734e.tar.gz"
  version "0.2.0"
  sha256 "96c2f2a1ea33057fd5ec00af95d33239060e14c45cfbecaebdbcf11eb859b1ba"
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

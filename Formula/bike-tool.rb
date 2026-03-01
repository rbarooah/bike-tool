class BikeTool < Formula
  desc "CLI for reading and safely editing Bike.app .bike outline files"
  homepage "https://github.com/rbarooah/bike-tool"
  url "https://github.com/rbarooah/bike-tool/archive/02d3009254742d3d982bff844cd3a1c3a1ac38de.tar.gz"
  version "0.2.2"
  sha256 "30bef19b5c9be1039c88ace76bfb0e5a9bd96cf315dc97a8c8ce1d1e167df05a"
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

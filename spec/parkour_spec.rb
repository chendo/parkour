require "spec_helper"
require "securerandom"
require "benchmark"

describe Parkour do
  it "runs stuff" do
    Parkour.trace(filters: [/./]) do
      3.times do
        sleep rand
      end
      3.times { sleep rand }
    end
  end

  Benchmark.bm do |x|
    x.report {
      Parkour.trace(filters: []) do
        it "with trace" do
          1000.times { SecureRandom.hex(10) }
        end
      end
    }
  end

  Benchmark.bm do |x|
    x.report {
      Parkour.trace(filters: [/NOMATCHY/]) do
        it "with no match trace" do
          1000.times { SecureRandom.hex(10) }
        end
      end
    }
  end

  Benchmark.bm do |x|
    x.report {
      it "without trace" do
        1000.times { SecureRandom.hex(10) }
      end
    }
  end

end

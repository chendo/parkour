require "spec_helper"

describe Parkour do
  it "runs stuff" do
    Parkour.trace(filters: [/./]) do
      3.times do
        sleep rand
      end
      3.times { sleep rand }
    end
  end
end

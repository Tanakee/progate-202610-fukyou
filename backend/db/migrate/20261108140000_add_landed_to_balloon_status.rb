class AddLandedToBalloonStatus < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :balloons, "status IN ('flying', 'collected', 'lost')", name: "balloons_status_check"
    add_check_constraint :balloons, "status IN ('flying', 'collected', 'lost', 'landed')", name: "balloons_status_check"
  end
end

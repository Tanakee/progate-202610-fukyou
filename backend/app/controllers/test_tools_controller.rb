class TestToolsController < ApplicationController
  prepend_before_action :require_test_environment

  # collected_on は履歴として残し、その回収だけを当日の上限判定から外す。
  def reset_favorite_limit
    count = current_user.with_lock do
      current_user.favorites.where(collected_on: Date.current, daily_limit_exempt: false)
        .update_all(daily_limit_exempt: true, updated_at: Time.current)
    end

    render json: { reset_count: count }
  end

  def reposition_balloons
    TestBalloonPlacement.launch_idle_tracks(except: current_user)
    count = TestBalloonPlacement.call
    BalloonsChannel.broadcast_snapshot
    render json: { updated_count: count }
  end

  private
    def require_test_environment
      head :not_found unless Rails.env.development? || Rails.env.test?
    end
end

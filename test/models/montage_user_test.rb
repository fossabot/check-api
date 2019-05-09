require_relative '../test_helper'

class MontageUserTest < ActiveSupport::TestCase
  def setup
    @user = create_user(name: 'Foo Bar', login: 'foo_bar', is_admin: false).extend(Montage::User)
  end

  test "should return when the user was created" do
    assert_kind_of String, @user.date_joined
  end

  test "should return if the user accepted the terms" do
    assert !@user.accepted_nda
    @user.last_accepted_terms_at = Time.now
    @user.save!
    assert @user.accepted_nda
  end

  test "should return user first name" do
    assert_equal 'Foo', @user.first_name
  end

  test "should return user last name" do
    assert_equal 'Bar', @user.last_name
  end

  test "should return if the user is a super user" do
    assert !@user.is_superuser
    @user.is_admin = true
    @user.save!
    assert @user.is_superuser
  end

  test "should return the last time the user logged in" do
    assert_kind_of String, @user.last_login
  end

  test "should return the profile image URL" do
    assert_match /^http/, @user.profile_img_url
  end

  test "should return the username" do
    assert_equal 'foo_bar', @user.username
  end
end 

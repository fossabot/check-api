require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class TeamUserMailerTest < ActionMailer::TestCase

  test "should send request to join email" do
    t = create_team
    o1 = create_user email: 'owner1@mail.com'
    o2 = create_user email: 'owner2@mail.com'
    u = create_user email: 'user@mail.com'
    create_team_user team: t, user: o1, role: 'owner'
    create_team_user team: t, user: o2, role: 'owner'
    create_team_user team: t, user: u, role: 'contributor'
    r = create_user

    email = TeamUserMailer.request_to_join(t, u)
    
    assert_emails 1 do
      email.deliver_now
    end
    
    assert_equal [CONFIG['default_mail']], email.from
    assert_equal ['owner1@mail.com', 'owner2@mail.com'], email.to
    assert_match "/team/#{t.id}/members", email.body.parts.first.to_s
  end

  test "should send request to join accepted email" do
    t = create_team
    u = create_user email: 'user@mail.com'

    email = TeamUserMailer.request_to_join_processed(t, u, true)
    
    assert_emails 1 do
      email.deliver_now
    end
    
    assert_equal [CONFIG['default_mail']], email.from
    assert_equal ['user@mail.com'], email.to
    assert_match "accepted", email.body.parts.first.to_s
  end

  test "should send request to join rejected email" do
    t = create_team
    u = create_user email: 'user@mail.com'

    email = TeamUserMailer.request_to_join_processed(t, u, false)
    
    assert_emails 1 do
      email.deliver_now
    end
    
    assert_equal [CONFIG['default_mail']], email.from
    assert_equal ['user@mail.com'], email.to
    assert_match "rejected", email.body.parts.first.to_s
  end
end
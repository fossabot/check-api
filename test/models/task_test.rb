require_relative '../test_helper'

class TaskTest < ActiveSupport::TestCase
  def setup
    super
    require 'sidekiq/testing'
    Sidekiq::Testing.inline!
    create_task_status_stuff
  end

  test "should create task" do
    t = nil
    assert_difference 'Task.length' do
      t = create_task
    end
    assert_not_nil t.jsonoptions
    assert_not_nil t.content
  end

  test "should not create task with blank label" do
    assert_no_difference 'Task.length' do
      assert_raises ActiveRecord::RecordInvalid do
        create_task label: nil
      end
    end
  end

  test "should not create task with invalid type" do
    assert_no_difference 'Task.length' do
      assert_raises ActiveRecord::RecordInvalid do
        create_task type: 'invalid'
      end
    end
  end

  test "should create task without description" do
    assert_difference 'Task.length' do
      create_task description: nil
    end
  end

  test "should create task without options" do
    assert_difference 'Task.length' do
      create_task options: nil
    end
  end

  test "should not create task if options is not an array" do
    assert_no_difference 'Task.length' do
      assert_raises ActiveRecord::RecordInvalid do
        create_task options: {}
      end
    end
  end

  test "should parse JSON options" do
    t = Task.new
    t.jsonoptions = ['foo', 'bar'].to_json
    assert_equal ['foo', 'bar'], t.options
  end

  test "should set initial status" do
    t = create_task status: nil
    assert_equal 'unresolved', t.reload.status
  end

  test "should add response to task" do
    t = create_task
    assert_equal 'unresolved', t.reload.status
    at = create_annotation_type annotation_type: 'response'
    create_field_instance annotation_type_object: at, name: 'response_test'
    t.response = { annotation_type: 'response', set_fields: { response_test: 'test' }.to_json }.to_json
    t.save!
    assert_equal 'resolved', t.reload.status
  end

  test "should get task responses" do
    t = create_task
    assert_equal [], t.responses
    at = create_annotation_type annotation_type: 'task_response'
    ft2 = create_field_type field_type: 'text'
    assert_equal [], t.reload.responses
    create_field_instance annotation_type_object: at, field_type_object: ft2, name: 'response'
    t.disable_es_callbacks = true
    t.response = { annotation_type: 'task_response', set_fields: { response: 'Test' }.to_json }.to_json
    t.save!
    assert_match /Test/, t.reload.responses.first.content.inspect
  end

  test "should delete responses when task is deleted" do
    at = create_annotation_type annotation_type: 'task_response'
    ft2 = create_field_type field_type: 'text'
    create_field_instance annotation_type_object: at, field_type_object: ft2, name: 'response'
    Dynamic.delete_all
    DynamicAnnotation::Field.delete_all
    t = create_task
    t.disable_es_callbacks = true
    t.response = { annotation_type: 'task_response', set_fields: { response: 'Test' }.to_json }.to_json
    t.save!
    r = t.responses.first
    assert_not_nil Annotation.where(id: r.id).last
    assert_equal 2, DynamicAnnotation::Field.count
    assert_equal 5, Dynamic.count
    t.disable_es_callbacks = true
    t.destroy
    assert_nil Annotation.where(id: r.id).last
    assert_equal 2, Dynamic.count
    assert_equal 0, DynamicAnnotation::Field.count
  end

  test "should notify on Slack when task is assigned" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      u1 = create_user
      create_team_user user: u1, team: t
      u2 = create_user
      create_team_user user: u2, team: t

      tk.assigned_to_ids = u2.id
      tk.save!
      assert_match /assigned/, tk.slack_notification_message[:pretext]

      tk.assigned_to_ids = ""
      tk.save!
      assert_match /unassigned/, tk.slack_notification_message[:pretext]
    end
  end

  test "should set assigner when task assigned" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      u2 = create_user
      create_team_user user: u2, team: t
      tk.save!
      tk.assign_user(u2.id)
      a = tk.assignments.last
      assert_equal u.id, a.assigner_id
    end
  end

  test "should notify on Slack when task is updated" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      tk.label = 'changed'
      tk.description = 'changed'
      tk.save!
      assert tk.sent_to_slack

      tk = Task.find(tk.id)
      c = create_comment annotated: tk
      assert_not tk.sent_to_slack
      assert c.sent_to_slack
    end
  end

  test "should notify on Slack when task is resolved" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    at = create_annotation_type annotation_type: 'task_response_free_text', label: 'Task'
    ft1 = create_field_type field_type: 'text_field', label: 'Text Field'
    fi1 = create_field_instance annotation_type_object: at, name: 'response_task', label: 'Response', field_type_object: ft1
    pm = create_project_media project: p

    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      tk.disable_es_callbacks = true
      tk.response = { annotation_type: 'task_response_free_text', set_fields: { response_task: 'Foo' }.to_json }.to_json
      tk.save!
      assert tk.response.sent_to_slack

      d = Dynamic.find(tk.response.id)
      d.set_fields = { response_task: 'Bar' }.to_json
      d.disable_es_callbacks = true
      d.save!
      assert d.sent_to_slack
    end
  end

  test "should notify by email when task is resolved" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    at = create_annotation_type annotation_type: 'task_response_free_text', label: 'Task'
    ft1 = create_field_type field_type: 'text_field', label: 'Text Field'
    fi1 = create_field_instance annotation_type_object: at, name: 'response_task', label: 'Response', field_type_object: ft1
    pm = create_project_media project: p
    tk = create_task annotator: u, annotated: pm
    u2 = create_user
    create_team_user team: t, user: u2
    with_current_user_and_team(u2, t) do
      tk.disable_es_callbacks = true
      tk.response = { annotation_type: 'task_response_free_text', set_fields: { response_task: 'Foo' }.to_json }.to_json
      tk.save!
      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        tk.status='resolved'
      end
    end
  end

  test "should notify on Slack when task is created" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      assert tk.sent_to_slack
    end
  end

  test "should get first response from task" do
    at = create_annotation_type annotation_type: 'task_response_free_text', label: 'Task'
    ft1 = create_field_type field_type: 'text_field', label: 'Text Field'
    fi1 = create_field_instance annotation_type_object: at, name: 'response_task', label: 'Response', field_type_object: ft1

    t = create_task
    assert_nil t.first_response

    t.disable_es_callbacks = true
    t.response = { annotation_type: 'task_response_free_text', set_fields: { response_task: 'Test' }.to_json }.to_json
    t.save!

    t = Task.find(t.id)
    assert_equal 'Test', t.first_response
  end

  test "should set slug when task is created" do
    t = create_task label: 'Where did it happen?'
    assert_equal 'where_did_it_happen', t.slug
  end

  test "should send Slack notification in background" do
    t = create_team slug: 'test'
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotator: u, annotated: pm
      tk = Task.find(tk.id)
      tk.data = { label: 'Foo', type: 'free_text' }.with_indifferent_access
      tk.save!
    end
  end

  test "should load task" do
    t = create_task
    assert_equal t, t.task
  end

  test "should have cached log count" do
    t = create_task
    assert_nil t.log_count
    c = create_comment annotated: t
    assert_equal 1, t.reload.log_count
    create_comment annotated: t
    assert_equal 2, t.reload.log_count
    c.destroy
    assert_equal 1, t.reload.log_count
  end

  test "should have log" do
    u = create_user is_admin: true
    t = create_team
    with_current_user_and_team(u, t) do
      tk = create_task
      assert_equal 0, tk.reload.log.count
      create_comment annotated: tk
      assert_equal 1, tk.reload.log.count
      create_comment annotated: tk
      assert_equal 2, tk.reload.log.count
    end
  end

  test "should update parent log count when comment is added to task" do
    u = create_user is_admin: true
    t = create_team
    p = create_project team: t
    pm = create_project_media project: p
    tk = create_task annotated: pm
    with_current_user_and_team(u, t) do
      assert_equal 0, pm.reload.cached_annotations_count
      create_comment annotated: tk
      assert_equal 2, pm.reload.cached_annotations_count
      c = create_comment annotated: tk
      assert_equal 4, pm.reload.cached_annotations_count
    end
  end

  test "should save comment in version" do
    u = create_user is_admin: true
    t = create_team
    p = create_project team: t
    pm = create_project_media project: p
    with_current_user_and_team(u, t) do
      tk = create_task annotated: pm
      c = create_comment annotated: tk, text: 'Foo Bar'
      meta = pm.reload.get_versions_log.where(event_type: 'update_task').last.meta
      assert_equal 'Foo Bar', JSON.parse(meta)['data']['text']
    end
  end

  test "should accept suggestion from bot" do
    text = create_field_type field_type: 'text', label: 'Text'
    json = create_field_type field_type: 'json', label: 'JSON'
    at = create_annotation_type annotation_type: 'task_response_free_text', label: 'Task Response Free Text'
    create_field_instance annotation_type_object: at, name: 'review_free_text', label: 'Review', field_type_object: json, optional: true
    create_field_instance annotation_type_object: at, name: 'response_free_text', label: 'Response', field_type_object: text, optional: false
    create_field_instance annotation_type_object: at, name: 'suggestion_free_text', label: 'Suggestion', field_type_object: json, optional: true

    tb = create_team_bot
    t = create_task type: 'free_text'
    assert_raises ActiveRecord::RecordInvalid do
      t.response = { annotation_type: 'task_response_free_text', set_fields: { response_free_text: '', suggestion_free_text: 'invalid' }.to_json }.to_json
    end
    t.response = { annotation_type: 'task_response_free_text', set_fields: { response_free_text: '', suggestion_free_text: { suggestion: 'Test', comment: 'Nothing' }.to_json }.to_json }.to_json
    t.save!
    assert_equal '', t.reload.first_response

    t = Task.find t.id
    t.accept_suggestion = 0
    t.save!
    assert_equal 'Test', t.reload.first_response

    t = create_task type: 'free_text'
    t.response = { annotation_type: 'task_response_free_text', set_fields: { response_free_text: '', suggestion_free_text: { suggestion: 'Test', comment: 'Nothing' }.to_json }.to_json }.to_json
    t.save!
    assert_equal '', t.reload.first_response

    t = Task.find t.id
    t.reject_suggestion = 0
    t.save!
    assert_equal '', t.reload.first_response

    u = create_user is_admin: true
    with_current_user_and_team(u, create_team) do
      t = create_task type: 'free_text'
      assert_nil t.reload.suggestions_count
      t.response = { annotation_type: 'task_response_free_text', set_fields: { response_free_text: '', suggestion_free_text: { suggestion: 'Test', comment: 'Nothing' }.to_json }.to_json }.to_json
      assert_equal 1, Task.find(t.id).suggestions_count
      f = t.responses.first.get_fields.select{ |f| f.field_name =~ /suggestion/ }.last
      assert_equal 'Task', f.versions.last.associated_type
      assert_equal t.id, f.versions.last.associated_id
    end
  end

  test "should resolve task if response is submitted and task is not assigned to anyone" do
    at = create_annotation_type annotation_type: 'response'
    create_field_instance annotation_type_object: at, name: 'response_test'
    t = create_team
    p = create_project team: t
    pm = create_project_media annotated: pm
    tk = create_task annotated: pm
    tk.response = { annotation_type: 'response', set_fields: { response_test: 'test' }.to_json }.to_json
    tk.save!
    assert_equal 'resolved', tk.reload.status
  end

  test "should resolve task if response is submitted by all assigned users" do
    at = create_annotation_type annotation_type: 'task_response'
    create_field_instance annotation_type_object: at, name: 'response_test'
    t = create_team
    p = create_project team: t
    pm = create_project_media project: p
    tk = create_task annotated: pm
    u1 = create_user
    u2 = create_user
    create_team_user team: t, user: u1, role: 'annotator'
    create_team_user team: t, user: u2, role: 'annotator'
    tk.assign_user(u1.id)
    tk.assign_user(u2.id)
    User.current = u1
    tk = Task.find(tk.id)
    tk.response = { annotation_type: 'task_response', set_fields: { response_test: 'test' }.to_json }.to_json
    tk.save!
    assert_equal 'unresolved', tk.reload.status
    User.current = u2
    tk = Task.find(tk.id)
    tk.response = { annotation_type: 'task_response', set_fields: { response_test: 'test' }.to_json }.to_json
    tk.save!
    assert_equal 'resolved', tk.reload.status
  end

  test "should not resolve task if response is not submitted" do
    t = create_task
    assert !t.must_resolve_task({ 'set_fields' => {} })
  end

  test "should get first response" do
    at = create_annotation_type annotation_type: 'task_response'
    create_field_instance annotation_type_object: at, name: 'response_test'
    t = create_team
    p = create_project team: t
    pm = create_project_media project: p
    tk = create_task annotated: pm
    u1 = create_user
    u2 = create_user
    create_team_user team: t, user: u1, role: 'annotator'
    create_team_user team: t, user: u2
    User.current = u1
    tk = Task.find(tk.id)
    tk.response = { annotation_type: 'task_response', set_fields: { response_test: 'foo' }.to_json }.to_json
    tk.save!
    User.current = nil
    tk = Task.find(tk.id)
    tk.response = { annotation_type: 'task_response', set_fields: { response_test: 'bar' }.to_json }.to_json
    tk.save!
    User.current = u1
    tk = Task.find(tk.id)
    assert_equal 'foo', tk.first_response
    User.current = u2
    tk = Task.find(tk.id)
    assert_equal 'bar', tk.first_response
  end

  test "should reopen task" do
    t = create_team
    p = create_project team: t
    pm = create_project_media project: p
    tk = create_task annotated: pm
    tk.status = 'resolved'
    tk.save!
    u = create_user
    create_team_user team: t, user: u, role: 'annotator'
    assert_equal 'resolved', tk.reload.status
    tk.assign_user(u.id)
    assert_equal 'unresolved', tk.reload.status
  end

  test "should get status label" do
    t = create_task
    assert_equal 'Unresolved', t.last_task_status_label
  end

  test "should return if task is required for a user" do
    u = create_user
    t = create_team
    create_team_user team: t, user: u
    p = create_project team: t
    pm = create_project_media project: p
    t1 = create_task annotated: pm
    t2 = create_task required: true, annotated: pm
    t3 = create_task required: true, annotated: pm
    t3.assign_user(u.id)
    assert !t1.reload.required_for_user(u.id)
    assert !t2.reload.required_for_user(u.id)
    assert t3.reload.required_for_user(u.id)
  end

  test "should update user assignments when task requirement changes" do
    at = create_annotation_type annotation_type: 'task_response'
    ft2 = create_field_type field_type: 'text'
    create_field_instance annotation_type_object: at, field_type_object: ft2, name: 'response'
    u = create_user is_admin: true
    t = create_team
    create_team_user team: t, user: u
    p = create_project team: t
    pm = create_project_media project: p
    tk = create_task annotated: pm, required: true
    tk.assign_user(u.id)
    tk = create_task annotated: pm, required: true
    tk.assign_user(u.id)
    assert_equal 0, pm.assignments_progress[:answered]
    assert_equal 0, pm.assignments_progress[:total]
    with_current_user_and_team(u ,t) do
      tk.response = { annotation_type: 'task_response', set_fields: { response: 'Test' }.to_json }.to_json
      tk.save!
      assert_equal 1, pm.assignments_progress[:answered]
      assert_equal 2, pm.assignments_progress[:total]
      tk.required = false
      tk.save!
      assert_equal 0, pm.assignments_progress[:answered]
      assert_equal 1, pm.assignments_progress[:total]
      assert_not_nil tk.first_response_version
      assert_kind_of PaperTrail::Version, tk.first_response_version
    end
  end
end

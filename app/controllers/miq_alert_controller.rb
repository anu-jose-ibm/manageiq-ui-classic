class MiqAlertController < ApplicationController
  before_action :check_privileges
  before_action :get_session_data
  after_action :cleanup_action
  after_action :set_session_data

  include Mixins::GenericFormMixin
  include Mixins::GenericListMixin
  include Mixins::GenericSessionMixin
  include Mixins::GenericShowMixin
  include Mixins::BreadcrumbsMixin
  include Mixins::PolicyMixin

  def title
    @title = _("Alerts")
  end

  SEVERITIES = {"info" => N_('Info'), "warning" => N_('Warning'), "error" => N_('Error')}.freeze

  def alert_edit_cancel
    @alert = params[:id] ? MiqAlert.find_by(:id => params[:id]) : MiqAlert.new
    if @alert.id.blank?
      flash_msg = _("Add of new Alert was cancelled by the user")
    else
      flash_msg = _("Edit of Alert \"%{name}\" was cancelled by the user") % {:name => @alert.description}
    end
    @edit = session[:edit] = nil # clean out the saved info
    session[:changed] = false
    javascript_redirect(:action => @lastaction, :id => params[:id], :flash_msg => flash_msg)
  end

  def alert_edit_save_add
    id = params[:id] && params[:button] != "add" ? params[:id] : "new"
    return unless load_edit("miq_alert_edit__#{id}")

    alert = @alert = @edit[:alert_id] ? MiqAlert.find(@edit[:alert_id]) : MiqAlert.new
    alert_set_record_vars(alert)

    unless alert_valid_record?(alert) && alert.valid? && !@flash_array && alert.save
      alert.errors.each do |error|
        add_flash("#{error.attribute.to_s.capitalize} #{error.message}", :error)
      end
      javascript_flash
      return
    end

    AuditEvent.success(build_saved_audit(alert, @edit))
    flash_key = params[:button] == 'save' ? _("Alert \"%{name}\" was saved") : _("Alert \"%{name}\" was added")
    flash_msg = (flash_key % {:name => @edit[:new][:description]})
    @edit = session[:edit] = nil # clean out the saved info
    session[:changed] = @changed = false
    javascript_redirect(:controller => 'miq_alert',
                        :action     => params[:button] == 'save' ? @lastaction : "show_list", # after copy redirect to list
                        :id         => params[:id],
                        :flash_msg  => flash_msg)
  end

  def alert_edit_reset
    alert_build_edit_screen
    javascript_redirect(:action        => 'edit',
                        :id            => params[:id],
                        :flash_msg     => _("All changes have been reset"),
                        :flash_warning => true) if params[:button] == "reset"
  end

  def new
    alert_edit_reset
  end

  def copy
    @_params[:id] ||= find_checked_items[0]
    alert_edit_reset
  end

  def edit
    @_params[:pressed] ||= "miq_alert_edit"
    assert_privileges(params[:pressed]) if params[:pressed]
    case params[:button]
    when "cancel"
      alert_edit_cancel
    when "save", "add"
      alert_edit_save_add
    when "reset", nil # Reset or first time in
      @_params[:id] ||= find_checked_items[0]
      @redirect_id = params[:id] if params[:id]
      @refresh_partial = "edit"
      alert_edit_reset
    end
  end

  def alert_field_changed
    return unless load_edit("miq_alert_edit__#{params[:id]}")

    @alert = @edit[:alert_id] ? MiqAlert.find(@edit[:alert_id]) : MiqAlert.new

    copy_params_if_present(@edit[:new], params, %i[description event_name])
    @edit[:new][:enabled] = params[:enabled_cb] == "1" if params.key?(:enabled_cb)
    @edit[:new][:severity] = params[:miq_alert_severity] if params.key?(:miq_alert_severity)
    if params[:exp_event]
      @edit[:new][:exp_event] = params[:exp_event] == "_hourly_timer_" ? params[:exp_event] : params[:exp_event].to_i
      @edit[:new][:repeat_time] = alert_default_repeat_time
    end
    @edit[:new][:repeat_time] = params[:repeat_time].to_i if params[:repeat_time]

    if params[:miq_alert_db]
      @edit[:new][:db] = params[:miq_alert_db]
      @edit[:expression_types] = MiqAlert.expression_types(@edit[:new][:db])
      if @edit[:expression_types].blank?
        alert_build_blank_exp
      else
        @edit[:new][:expression] = {:eval_method => @edit[:expression_types].invert.sort.to_a.first.last,
                                    :mode        => "internal"}
        @edit[:new][:expression][:options] = {}
        @edit[:expression_options] = MiqAlert.expression_options(@edit[:new][:expression][:eval_method])
        alert_build_exp_options_info
      end
      @edit[:new][:exp_event] = %w[ContainerNode ContainerProject].include?(@edit[:new][:db]) ? nil : @edit[:current][:exp_event]
    end

    if params.key?(:exp_name)
      if params[:exp_name].blank? # Set to MiqExpression
        alert_build_blank_exp
      else
        @edit[:new][:expression] = {:eval_method => params[:exp_name], :mode => "internal"}
        @edit[:new][:expression][:options] = {}
        @edit[:expression_options] = MiqAlert.expression_options(@edit[:new][:expression][:eval_method])
        alert_build_exp_options_info
      end
      @edit[:new][:repeat_time] = alert_default_repeat_time if apply_default_repeat_time?
    end

    copy_params_if_present(@edit[:new][:expression][:options], params, %i[freq_threshold
                                                                          perf_column
                                                                          value_threshold
                                                                          trend_direction
                                                                          trend_steepness
                                                                          event_log_message_filter_value
                                                                          event_log_name
                                                                          event_log_level
                                                                          event_log_event_id
                                                                          event_log_source
                                                                          debug_trace
                                                                          value_mw_greater_than
                                                                          value_mw_less_than
                                                                          value_mw_garbage_collector
                                                                          value_mw_threshold])
    @edit[:new][:expression][:options][:event_types] = [params[:event_types]].reject(&:blank?) if params[:event_types]
    @edit[:new][:expression][:options][:time_threshold] = params[:time_threshold].to_i if params[:time_threshold]
    @edit[:new][:expression][:options][:hourly_time_threshold] = params[:hourly_time_threshold].to_i if params[:hourly_time_threshold]
    if params[:perf_column]
      @edit[:perf_column_unit] = alert_get_perf_column_unit(@edit[:perf_column_options][@edit[:new][:expression][:options][:perf_column]])
    end
    @edit[:new][:expression][:options][:operator] = params[:select_operator] if params[:select_operator]
    if params[:trend_direction]
      @edit[:new][:expression][:options].delete(:trend_steepness) unless params[:trend_direction].ends_with?("more_than")
      @edit[:perf_column_unit] = alert_get_perf_column_unit(@edit[:perf_column_options][@edit[:new][:expression][:options][:perf_column]])
    end
    @edit[:new][:expression][:options][:rt_time_threshold] = params[:rt_time_threshold].to_i if params[:rt_time_threshold]
    @edit[:new][:expression][:options][:event_log_message_filter_type] = params[:select_event_log_message_filter_type] if params[:select_event_log_message_filter_type]
    @edit[:new][:expression][:options][:hdw_attr] = params[:select_hdw_attr] if params[:select_hdw_attr]

    # Handle VMware Alarm parms
    if params.key?(:select_ems_id)
      if params[:select_ems_id].blank?
        @edit[:new][:expression][:options][:ems_id] = nil
        @edit[:new][:expression][:options][:ems_alarm_mor] = nil
        @edit[:new][:expression][:options][:ems_alarm_name] = nil
      else
        @edit[:new][:expression][:options][:ems_id] = params[:select_ems_id].to_i
        @edit[:ems_alarms] = alert_build_ems_alarms
      end
    end
    if params.key?(:select_ems_alarm_mor)
      if params[:select_ems_alarm_mor].blank?
        @edit[:new][:expression][:options][:ems_alarm_mor] = nil
        @edit[:new][:expression][:options][:ems_alarm_name] = nil
      else
        @edit[:new][:expression][:options][:ems_alarm_mor] = params[:select_ems_alarm_mor]
        @edit[:new][:expression][:options][:ems_alarm_name] = @edit[:ems_alarms][params[:select_ems_alarm_mor]]
      end
    end

    if params[:select_mw_operator]
      @edit[:new][:expression][:options][:mw_operator] = params[:select_mw_operator]
    end

    @edit[:new][:email][:from] = params[:from] if params.key?(:from)
    @edit[:email] = params[:email] if params.key?(:email)
    if params[:user_email]
      @edit[:new][:email][:to] ||= []
      @edit[:new][:email][:to].push(params[:user_email])
      @edit[:new][:email][:to].sort!
      @edit[:user_emails].delete(params[:user_email])
    end

    if params[:button] == "add_email"
      @edit[:new][:email][:to] ||= []
      @edit[:new][:email][:to].push(@edit[:email]) unless @edit[:email].blank? || @edit[:new][:email][:to].include?(@edit[:email])
      @edit[:new][:email][:to].sort!
      @edit[:email] = nil
    end

    if params[:remove_email]
      @edit[:new][:email][:to].delete(params[:remove_email])
      build_user_emails_for_edit
    end

    if params[:user_email] || params[:button] == "add_email" || params[:remove_email]
      # rebuild hash to hold user's email along with name if user record was found for display, defined as hash so only email id can be sent from form to be deleted from array above
      @email_to = {}
      @edit[:new][:email][:to].each_with_index do |e, _e_idx|
        u = User.find_by(:email => e)
        @email_to[e] = u ? "#{u.name} (#{e})" : e
      end
    end

    @alert_snmp_refresh = build_snmp_options(:snmp, @edit[:new][:send_snmp])

    @edit[:new][:send_email]     = (params[:send_email_cb] == "1") if params.key?(:send_email_cb)
    @edit[:new][:send_snmp]      = (params[:send_snmp_cb] == "1") if params.key?(:send_snmp_cb)
    @edit[:new][:send_evm_event] = (params[:send_evm_event_cb] == "1") if params.key?(:send_evm_event_cb)
    @edit[:new][:send_event]     = (params[:send_event_cb] == "1") if params.key?(:send_event_cb)

    @alert_refresh = %i[exp_event exp_name miq_alert_db perf_column select_ems_id
                        send_email_cb send_event_cb send_snmp_cb trend_direction].any? { |key| params.key?(key) }
    @to_email_refresh = params[:user_email] || params[:remove_email] || params[:button] == "add_email"
    send_button_changes
  end

  # Get information for an alert
  def show
    super
    @alert = @record
    @email_to = []
    if @alert.responds_to_events == "_hourly_timer_"
      @event = _("Hourly Timer")
    else
      e = MiqEventDefinition.find_by(:name => @alert.responds_to_events)
      @event = e.nil? ? _("<No Event configured>") : e.etype.description + ": " + e.description
    end
    if @alert.options && @alert.options[:notifications] && @alert.options[:notifications][:email] && @alert.options[:notifications][:email][:to]
      @alert.options[:notifications][:email][:to].each do |to|
        user = User.find_by(:email => to)
        @email_to.push(user ? "#{user.name} (#{to})" : to)
      end
    end

    @expression_table = exp_build_table(@alert.expression.exp) if @alert.expression.kind_of?(MiqExpression)
    @alert_profiles = @alert.memberof.sort_by { |p| p.description.downcase }

    if @alert.expression && !@alert.expression.kind_of?(MiqExpression) # Get the EMS if it's in the expression
      @ems = ExtManagementSystem.find_by(:id => @alert.expression[:options][:ems_id])
    end
    if @alert.expression.kind_of?(Hash) && @alert.expression[:eval_method]
      @expression_options = MiqAlert.expression_options(@alert.expression[:eval_method])
      @expression_options.each do |eo|
        case eo[:name]
        when :perf_column
          @perf_column_unit = alert_get_perf_column_unit(eo[:values][@alert.db][@alert.expression[:options][:perf_column]])
        end
      end
    end
  end

  private

  def display_driving_event?
    (@edit[:new][:expression][:eval_method] && @edit[:new][:expression][:eval_method] != "nothing") ||
      %w[ContainerNode ContainerProject].include?(@edit[:new][:db])
  end
  helper_method :display_driving_event?

  def alert_build_edit_screen
    @edit = {}
    @edit[:new] = {}
    @edit[:current] = {}

    if params[:action] == "copy" # If copying, create a new alert based on the original
      # skip record id when copying attributes
      @alert = MiqAlert.find(params[:id]).dup
    else
      # Get existing record if edit action or create new record
      @alert = params[:id] ? MiqAlert.find(params[:id]) : MiqAlert.new
      @alert.enabled = true unless @alert.id # Default enabled to true if new record
    end
    @record = @alert
    @edit[:key] = "miq_alert_edit__#{@alert.id || "new"}"
    @edit[:rec_id] = @alert.id || nil

    @edit[:alert_id] = @alert.id
    @edit[:new][:email] = {}
    @edit[:new][:snmp] = {}
    if @alert.options && @alert.options[:notifications] && @alert.options[:notifications][:email]
      @edit[:new][:email] = copy_hash(@alert.options[:notifications][:email])
      @edit[:new][:send_email] = true
      # build hash to hold user's email along with name if user record was found for display, defined as hash so only email id can be sent from form to be deleted from array above
      @email_to = {}
      if @edit[:new][:email] && @edit[:new][:email][:to]
        @edit[:new][:email][:to].each_with_index do |e, _e_idx|
          u = User.find_by(:email => e)
          @email_to[e] = u ? "#{u.name} (#{e})" : e
        end
      end
    end
    if @alert.options && @alert.options[:notifications] && @alert.options[:notifications][:snmp]
      @edit[:new][:snmp] = copy_hash(@alert.options[:notifications][:snmp])
      @edit[:new][:snmp][:host] = @alert.options[:notifications][:snmp][:host] ? @alert.options[:notifications][:snmp][:host].to_a : Array.new(3)
      @edit[:new][:send_snmp] = true
    end
    @edit[:new][:snmp][:host] ||= Array.new(3)
    if @alert.options && @alert.options[:notifications] && @alert.options[:notifications][:evm_event]
      @edit[:new][:send_evm_event] = true
    end
    if @alert.options && @alert.options[:notifications] && @alert.options[:notifications][:automate]
      @edit[:new][:event_name] = @alert.options[:notifications][:automate][:event_name]
      @edit[:new][:send_event] = true
    end
    @edit[:new][:send_snmp] ||= false
    @edit[:new][:send_evm_event] ||= false
    @edit[:new][:send_event] ||= false
    alert_build_snmp_variables
    build_user_emails_for_edit

    # Build hash of arrays of all events by event type
    @edit[:events] = {}
    MiqEventDefinition.all_control_events.each do |e|
      @edit[:events][e.id] = (_(e.etype.description) + ": " + _(e.description))
    end

    # Build hash of all mgmt systems by id
    @edit[:emss] = {}
    ExtManagementSystem.all.each do |e|
      @edit[:emss][e.id] = e.name
    end

    @edit[:new][:description] = @alert.description
    @edit[:new][:enabled] = @alert.enabled == true
    @edit[:new][:severity] = @alert.severity
    @edit[:new][:db] = @alert.db.nil? ? "Vm" : @alert.db
    @edit[:expression_types] = MiqAlert.expression_types(@edit[:new][:db])

    if @alert.expression.kind_of?(MiqExpression)
      build_expression(@alert, @edit[:new][:db])
    elsif @alert.expression.nil?
      @edit[:new][:expression] = {:eval_method => @edit[:expression_types].invert.sort.to_a.first.last, :mode => "internal"}
      @edit[:new][:expression][:options] = {}
      @edit[:expression_options] = MiqAlert.expression_options(@edit[:new][:expression][:eval_method])
      alert_build_exp_options_info
    else
      @edit[:new][:expression] = copy_hash(@alert.expression) # Copy the builtin exp hash
      @edit[:expression_options] = MiqAlert.expression_options(@edit[:new][:expression][:eval_method])
      alert_build_exp_options_info
    end

    if @alert.expression.kind_of?(MiqExpression) # If an exp alert, get the event id
      if @alert.responds_to_events == "_hourly_timer_" # Check for hourly timer event
        @edit[:new][:exp_event] = @alert.responds_to_events
      else
        exp_event = MiqEventDefinition.find_by(:name => @alert.responds_to_events)
        @edit[:new][:exp_event] = exp_event.nil? ? nil : exp_event.id
      end
    elsif @alert.expression.kind_of?(Hash) && @alert.expression[:eval_method] == "nothing"
      if @alert.responds_to_events == "_hourly_timer_" # Check for hourly timer event
        @edit[:new][:exp_event] = @alert.responds_to_events
      else
        exp_event = MiqEventDefinition.find_by(:name => @alert.responds_to_events)
        @edit[:new][:exp_event] = exp_event.nil? ? nil : exp_event.id
      end
    end

    # Build hash of alarms if mgmt system option is present is present
    if !@alert.expression.kind_of?(MiqExpression) &&
      @edit[:new][:expression][:options] && @edit[:new][:expression][:options][:ems_id]
      @edit[:ems_alarms] = alert_build_ems_alarms
    end

    # Set the repeat time based on the existing options
    @edit[:new][:repeat_time] ||= @alert.options&.dig(:notifications, :delay_next_evaluation).presence || alert_default_repeat_time

    @edit[:current] = copy_hash(@edit[:new])

    @edit[:dbs] = {}
    MiqAlert.base_tables.each do |db|
      @edit[:dbs][db] = ui_lookup(:model => db)
    end
    @embedded = true
    @in_a_form = true
    @edit[:current][:add] = true if @edit[:alert_id].nil? # Force changed to be true if adding a record
    session[:changed] = (@edit[:new] != @edit[:current])
  end

  def alert_default_repeat_time
    if (@edit[:new][:expression][:eval_method] && @edit[:new][:expression][:eval_method] == "hourly_performance") ||
       @edit[:new][:exp_event] == "_hourly_timer_"
      1.hour.to_i
    elsif @edit[:new][:expression][:eval_method] && @edit[:new][:expression][:eval_method] == "dwh_generic"
      0.minutes.to_i
    else
      10.minutes.to_i
    end
  end

  def apply_default_repeat_time?
    event = @edit[:new]
    return true if event[:exp_event] == '_hourly_timer_'
    return false if event[:eval_method].nil?

    event[:eval_method] =~ /hourly_performance|dwh_generic/
  end

  def alert_get_perf_column_unit(val)
    return nil unless val

    e_point = val.rindex(')')
    s_point = val.rindex('(')
    res = e_point && s_point ? "#{val[s_point + 1..e_point - 1]} " : nil
    res
  end

  def alert_build_snmp_variables
    @edit[:new][:snmp][:snmp_version] = "v1" if @edit[:new][:snmp][:snmp_version].blank?
    @edit[:snmp_var_types] = MiqSnmp.available_types
    @edit[:new][:snmp][:variables] ||= []
    10.times do |i|
      @edit[:new][:snmp][:variables][i] ||= {}
      @edit[:new][:snmp][:variables][i][:oid] ||= ""
      @edit[:new][:snmp][:variables][i][:var_type] ||= "<None>"
      @edit[:new][:snmp][:variables][i][:value] ||= ""
    end
  end

  def alert_build_blank_exp
    @edit[:expression] ||= ApplicationController::Filter::Expression.new
    @edit[:expression][:expression] = []                                  # Store exps in an array
    @edit[:expression][:expression] = {"???" => "???"}                    # Set as new exp element
    @edit[:new][:expression] = copy_hash(@edit[:expression][:expression]) # Copy to new exp
    @edit[:expression_table] = exp_build_table_or_nil(@edit[:expression][:expression])

    @expkey = :expression                                               # Set expression key to expression
    @edit[@expkey].history.reset(@edit[:expression][:expression])
    @edit[:expression][:exp_table] = exp_build_table(@edit[:expression][:expression])
    @edit[:expression][:exp_model] = @edit[:new][:db]                   # Set model for the exp editor
  end

  def alert_build_exp_options_info
    MiqAlert.expression_options(@edit[:new][:expression][:eval_method]).each do |eo|
      case eo[:name]

      when :ems_id
        # Handle missing or blank ems id
        unless !@alert.expression ||
               ExtManagementSystem.exists?(@edit[:new][:expression][:options][:ems_id].to_i)
          @edit[:new][:expression][:options][:ems_id] = nil
          @edit[:new][:expression][:options][:ems_alarm_mor] = nil
        end
        if @edit[:emss].length == 1 # Set to first column if only 1 choice
          @edit[:new][:expression][:options][:ems_id] ||= @edit[:emss].invert.to_a.first.last
          @edit[:ems_alarms] = alert_build_ems_alarms
        end

      when :perf_column
        @edit[:new][:expression][:options][:perf_column] ||= eo[:values][@edit[:new][:db]].invert.min.last # Set to first column
        @edit[:perf_column_options] = eo[:values][@edit[:new][:db]] # storing perf_column values in hash to use them later for lookup to show units in UI
        @edit[:perf_column_unit] = alert_get_perf_column_unit(@edit[:perf_column_options][@edit[:new][:expression][:options][:perf_column]])
      when :value_threshold
        @edit[:new][:expression][:options][:value_threshold] ||= "" # Init value to blank
      when :trend_direction
        @edit[:new][:expression][:options][:trend_direction] ||= "none"
        @edit[:new][:expression][:options][:trend_steepness] ||= nil

      when :hdw_attr
        @edit[:hdw_attrs] = eo[:values].invert.sort
        @edit[:new][:expression][:options][:hdw_attr] ||= @edit[:hdw_attrs].first.last

      when :operator
        @edit[:operators] = eo[:values]
        @edit[:new][:expression][:options][:operator] ||= eo[:values].first

      when :mw_operator
        @edit[:operators] = eo[:values]
        @edit[:new][:expression][:options][:mw_operator] ||= eo[:values].first

      when :event_log_message_filter_type
        @edit[:event_log_message_filter_types] = eo[:values]
        @edit[:new][:expression][:options][:event_log_message_filter_type] ||= eo[:values].first

      when :debug_trace
        @edit[:new][:expression][:options][:debug_trace] ||= "false"

      end
    end
  end

  def alert_build_pulldowns
    @sb[:alert] ||= {}

    # :event_types
    unless @sb[:alert][:events] # Only create this once
      vm_events = MiqAlert.expression_options("event_threshold").find { |eo| eo[:name] == :event_types }[:values] # Get the allowed events
      @sb[:alert][:events] ||= {}
      EmsEvent.event_groups.each_value do |v|
        name = v[:name]
        v[:detail]&.each do |d|
          @sb[:alert][:events][d] = name + ": " + d if vm_events.include?(d)
        end
        v[:critical]&.each do |c|
          @sb[:alert][:events][c] = name + ": " + c if vm_events.include?(c)
        end
      end
    end

    # :time_thresholds
    @sb[:alert][:time_thresholds] ||= {
      5.minutes.to_i => _("5 Minutes"), 10.minutes.to_i => _("10 Minutes"), 15.minutes.to_i => _("15 Minutes"),
      30.minutes.to_i => _("30 Minutes"), 1.hour.to_i => _("1 Hour"), 2.hours.to_i => _("2 Hours"),
      3.hours.to_i => _("3 Hours"), 4.hours.to_i => _("4 Hours"), 6.hours.to_i => _("6 Hours"),
      12.hours.to_i => _("12 Hours"), 1.day.to_i => _("1 Day")
    }

    # :hourly_time_thresholds
    @sb[:alert][:hourly_time_thresholds] ||= {
      1.hour.to_i => _("1 Hour"), 2.hours.to_i => _("2 Hours"), 3.hours.to_i => _("3 Hours"),
      4.hours.to_i => _("4 Hours"), 6.hours.to_i => _("6 Hours"), 12.hours.to_i => _("12 Hours"),
      1.day.to_i => _("1 Day")
    }

    # :rt_time_thresholds
    @sb[:alert][:rt_time_thresholds] ||= {
      1.minute.to_i => _("1 Minute"), 2.minutes.to_i => _("2 Minutes"), 3.minutes.to_i => _("3 Minutes"),
      4.minutes.to_i => _("4 Minutes"), 5.minutes.to_i => _("5 Minutes"), 10.minutes.to_i => _("10 Minutes"),
      15.minutes.to_i => _("15 Minutes"), 30.minutes.to_i => _("30 Minutes"), 1.hour.to_i => _("1 Hour"),
      2.hours.to_i => _("2 Hours")
    }

    # hourly_performance repeat times for Notify Every pull down
    @sb[:alert][:hourly_repeat_times] ||= @sb[:alert][:hourly_time_thresholds]

    # repeat times for Notify Every pull down
    @sb[:alert][:repeat_times] ||= {
      3.hours.to_i => _("3 Hours"), 4.hours.to_i => _("4 Hours"),
      6.hours.to_i => _("6 Hours"), 12.hours.to_i => _("12 Hours"), 1.day.to_i => _("1 Day")
    }.merge(@sb[:alert][:rt_time_thresholds])

    # repeat times for Notify Datawarehouse pull down
    @sb[:alert][:repeat_times_dwh] ||= {
      0.minutes.to_i => _("Always Notify")
    }
  end

  def alert_build_ems_alarms
    alarms = {}
    begin
      alarms = MiqAlert.ems_alarms(@edit[:new][:db], @edit[:new][:expression][:options][:ems_id])
    rescue StandardError => bang
      add_flash(_("Error during alarms: %{messages}") % {:messages => bang.message}, :error)
    end
    alarms
  end

  # Set alert record variables to new values
  def alert_set_record_vars(alert)
    alert.description = @edit[:new][:description]
    alert.enabled = @edit[:new][:enabled]
    alert.severity = @edit[:new][:severity]
    alert.db = @edit[:new][:db]
    if @edit[:new][:expression][:eval_method]
      alert.expression = copy_hash(@edit[:new][:expression])
      # nothing acts like an expression, exp event is needed
      if @edit[:new][:expression][:eval_method] == "nothing"
        alert.responds_to_events = if @edit[:new][:exp_event] == "_hourly_timer_"
                                     @edit[:new][:exp_event]
                                   elsif @edit[:new][:exp_event]&.positive?
                                     MiqEventDefinition.find(@edit[:new][:exp_event]).name
                                   end
      end
    else
      alert.expression = @edit[:new][:expression]["???"] ? nil : MiqExpression.new(@edit[:new][:expression])
      alert.responds_to_events = if @edit[:new][:exp_event] == "_hourly_timer_"
                                   @edit[:new][:exp_event]
                                 elsif @edit[:new][:exp_event]&.positive?
                                   MiqEventDefinition.find(@edit[:new][:exp_event]).name
                                 end
    end
    alert.options = {}
    alert.options[:notifications] = {}
    alert.options[:notifications][:delay_next_evaluation] = @edit[:new][:repeat_time]
    alert.options[:notifications][:email] = copy_hash(@edit[:new][:email]) if @edit[:new][:send_email]
    if @edit[:new][:send_snmp]
      # delete any blank entries from host array
      @edit[:new][:snmp][:host].delete_if { |x| x.nil? || x == "" }
      alert.options[:notifications][:snmp] = copy_hash(@edit[:new][:snmp])
    end
    alert.options[:notifications][:snmp] = copy_hash(@edit[:new][:snmp]) if @edit[:new][:send_snmp]
    alert.options[:notifications][:evm_event] = {} if @edit[:new][:send_evm_event] # Set as empty hash, no parms needed
    alert.options[:notifications][:automate] = {:event_name => @edit[:new][:event_name]} if @edit[:new][:send_event]
  end

  # Check alert record variables
  def alert_valid_record?(alert)
    if alert.expression.nil?
      add_flash(_("A valid expression must be present"), :error)
    end
    unless display_driving_event?
      add_flash(_("A Driving Event must be selected"), :error) if alert.responds_to_events.blank?
    end
    if alert.severity.nil?
      add_flash(_('Severity must be selected'), :error)
    end
    if alert.options[:notifications][:automate]
      add_flash(_("Event name is required"), :error) if alert.options[:notifications][:automate][:event_name].blank?
    end
    if alert.expression.kind_of?(Hash) && alert.expression[:eval_method] == 'event_threshold'
      add_flash(_("Event to Check is required"), :error) if alert.expression[:options][:event_types].blank?
    end

    if @edit.fetch_path(:new, :expression, :eval_method) == "realtime_performance"
      vt = @edit.fetch_path(:new, :expression, :options, :value_threshold)
      unless vt && is_integer?(vt)
        add_flash(_("Value Threshold must be an integer"), :error)
      end
      if @edit.fetch_path(:new, :expression, :options, :trend_direction).ends_with?("more_than")
        ts = @edit.fetch_path(:new, :expression, :options, :trend_steepness)
        unless ts && is_integer?(ts)
          add_flash(_("Trend Steepness must be an integer"), :error)
        end
      end
      unless @edit.fetch_path(:new, :expression, :options, :rt_time_threshold)
        add_flash(_("Time threshold for the field criteria must be selected"), :error)
      end
    end
    if %w[mw_heap_used mw_non_heap_used].include?(@edit.fetch_path(:new, :expression, :eval_method))
      value_greater_than = @edit.fetch_path(:new, :expression, :options, :value_mw_greater_than)
      non = @edit.fetch_path(:new, :expression, :eval_method) == "mw_non_heap_used" ? "Non" : ""
      an_integer = "an integer"
      between = "between 0 and 100"
      template_error = "%s %s Heap Max (%%) must be %s"
      min_max_error = "> %s Heap Max (%%) must be greater than < %s Heap Max (%%)"
      unless value_greater_than && is_integer?(value_greater_than)
        add_flash(_(template_error % [">", non, an_integer]), :error)
      end
      value_greater_than = value_greater_than.to_i
      unless value_greater_than.between?(0, 100)
        add_flash(_(template_error % [">", non, between]), :error)
      end
      value_less_than = @edit.fetch_path(:new, :expression, :options, :value_mw_less_than)
      unless value_less_than && is_integer?(value_less_than)
        add_flash(_(template_error % ["<", non, an_integer]), :error)
      end
      value_less_than = value_less_than.to_i
      unless value_less_than.between?(0, 100)
        add_flash(_(template_error % ["<", non, between]), :error)
      end
      if value_less_than && value_greater_than && (value_less_than >= value_greater_than)
        add_flash(_(min_max_error % [non, non]), :error)
      end
    end
    if @edit.fetch_path(:new, :expression, :eval_method) == "mw_accumulated_gc_duration"
      value_mw_garbage_collector = @edit.fetch_path(:new, :expression, :options, :value_mw_garbage_collector)
      unless value_mw_garbage_collector && is_integer?(value_mw_garbage_collector)
        add_flash(_("Duration Per Minute must be an integer"), :error)
      end
    end
    if %w[mw_tx_committed mw_tx_timeout mw_tx_heuristics mw_tx_application_rollbacks mw_tx_resource_rollbacks mw_tx_aborted].include?(@edit.fetch_path(:new, :expression, :eval_method))
      value_mw_threshold = @edit.fetch_path(:new, :expression, :options, :value_mw_threshold)
      unless value_mw_threshold && is_integer?(value_mw_threshold)
        add_flash(_("Number must be an integer"), :error)
      end
    end
    unless alert.options[:notifications][:email] ||
           alert.options[:notifications][:snmp] ||
           alert.options[:notifications][:evm_event] ||
           alert.options[:notifications][:automate]
      add_flash(_("At least one of E-mail, SNMP Trap, Timeline Event, or Management Event must be configured"),
                :error)
    end
    if alert.options[:notifications][:email]
      if alert.options[:notifications][:email][:to].blank?
        add_flash(_("At least one E-mail recipient must be configured"), :error)
      elsif alert.options[:notifications][:email][:to].find { |i| !i.to_s.email? }
        add_flash(_("One of e-mail addresses 'To' is not valid"), :error)
      elsif alert.options[:notifications][:email][:from].present? &&
            !alert.options[:notifications][:email][:from].email?
        add_flash(_("E-mail address 'From' is not valid"), :error)
      end
    end
    if alert.options[:notifications][:snmp]
      validate_snmp_options(alert.options[:notifications][:snmp])
      unless @flash_array
        alert.options[:notifications][:snmp][:variables] =
          @edit[:new][:snmp][:variables].reject { |var| var[:oid].blank? }
      end
    end
    @flash_array.nil?
  end

  def get_session_data
    @alert = MiqAlert.find_by(:id => params[:miq_grid_checks])
    @title = if @alert.present?
               _("Editing Alert \"%{name}\"") % {:name => @alert.description}
             else
               _("Adding a new Alert")
             end
    @layout =  "miq_alert"
    @lastaction = session[:miq_alert_lastaction]
    @display = session[:miq_alert_display]
    @current_page = session[:miq_alert_current_page]
    alert_build_pulldowns
  end

  def set_session_data
    super
    session[:layout]                 = @layout
    session[:miq_alert_current_page] = @current_page
  end

  def breadcrumbs_options
    {
      :breadcrumbs  => [
        {:title => _("Control")},
        {:title => _('Alerts'), :url => controller_url},
      ].compact,
      :record_title => :description,
    }
  end

  toolbar :miq_alert,:miq_alerts
  menu_section :con
end

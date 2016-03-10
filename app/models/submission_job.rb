class SubmissionJob < ActiveJob::Base

  queue_as :test_job

  def perform
    #Fork-off a new process resposible for collecting all submissions
    #Since windows doesn't support fork, the main process will have to collect
    #the submissions.
    # Fork is also skipped if in testing mode
    if RUBY_PLATFORM =~ /(:?mswin|mingw)/ || Rails.env.test?
      while collect_next_submission
      end
      return
    end

    m_logger = MarkusLogger.instance

    #Check to see if there is still a process running
    m_logger.log('Checking to see if there is already a submission collection' +
                 ' process running')

    # m_logger.log('Submission collection process still running, doing nothing')


    #We have to re-establish a separate database connection for each process
    db_connection = ActiveRecord::Base.remove_connection

      begin
        ActiveRecord::Base.establish_connection(db_connection)
        m_logger.log('Submission collection process established database' +
                     ' connection successfully')
        #Any custom tasks to be performed by the child can be given as a block
        if block_given?
          m_logger.log('Submission collection process now evaluating provided code block')
          yield
          m_logger.log('Submission collection process done evaluating provided code block')
        end
        Grouping.find_each do |grouping|
        
			return if grouping.nil?
			assignment = grouping.assignment
			m_logger = MarkusLogger.instance
			m_logger.log("Now collecting: #{assignment.short_identifier} for grouping: " +
						 "'#{grouping.id}'")
			time = assignment.submission_rule.calculate_collection_time.localtime
			# Create a new Submission by timestamp.
			# A Result is automatically attached to this Submission, thanks to some
			# callback logic inside the Submission model
			new_submission = Submission.create_by_timestamp(grouping, time)
			# Apply the SubmissionRule
			new_submission = assignment.submission_rule.apply_submission_rule(
			  new_submission)

			unless grouping.error_collecting
			  grouping.is_collected = true
			end

			grouping.save

        end
        m_logger.log('Submission collection process done')
        exit!(0)
      ensure
        ActiveRecord::Base.remove_connection
      end
      ActiveRecord::Base.establish_connection(db_connection)
      self.save
  end
  
    #Collect the next submission or return nil if there are none to be collected
  def collect_next_submission
    grouping = get_next_grouping_for_collection
    return if grouping.nil?
    assignment = grouping.assignment
    m_logger = MarkusLogger.instance
    m_logger.log("Now collecting: #{assignment.short_identifier} for grouping: " +
                 "'#{grouping.id}'")
    time = assignment.submission_rule.calculate_collection_time.localtime
    # Create a new Submission by timestamp.
    # A Result is automatically attached to this Submission, thanks to some
    # callback logic inside the Submission model
    new_submission = Submission.create_by_timestamp(grouping, time)
    # Apply the SubmissionRule
    new_submission = assignment.submission_rule.apply_submission_rule(
      new_submission)

    unless grouping.error_collecting
      grouping.is_collected = true
    end

    #remove_grouping_from_queue(grouping)
    grouping.save
  end

  def apply_penalty_or_add_grace_credits(grouping,
                                         apply_late_penalty,
                                         new_submission)
    if grouping.assignment.submission_rule.is_a? GracePeriodSubmissionRule
      # Return any grace credits previously deducted for this grouping.
      grouping.assignment.submission_rule.remove_deductions(new_submission)
    end
    if apply_late_penalty
      grouping.assignment.submission_rule.apply_submission_rule(new_submission)
    end

  end

end
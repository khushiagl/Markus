require 'json'
# Helper methods for Testing Framework forms
module AutomatedTestsHelper
  # This is the waiting list for automated testing. Once a test is requested,
  # it is enqueued and it is waiting for execution. Resque manages this queue.
  @queue = :test_waiting_list

  def fetch_latest_tokens_for_grouping(grouping)
    token = Token.find_by(grouping: grouping)
    if token
      token.reassign_tokens_if_new_day
    end
    token
  end

  def create_test_repo(assignment)
    # Create the automated test repository
    unless File.exist?(MarkusConfigurator
                            .markus_config_automated_tests_repository)
      FileUtils.mkdir(MarkusConfigurator
                          .markus_config_automated_tests_repository)
    end

    test_dir = File.join(MarkusConfigurator
                             .markus_config_automated_tests_repository,
                         assignment.short_identifier)
    unless File.exist?(test_dir)
      FileUtils.mkdir(test_dir)
    end
  end

  # Process Testing Framework form
  # - Process new and updated test files (additional validation to be done at the model level)
  def process_test_form(assignment, params, new_script)

    updated_script_files = {}
    updated_support_files = {}

    testscripts = params[:test_scripts_attributes] || []
    testsupporters = params[:test_support_files_attributes] || []

    # Create/Update test scripts
    testscripts.each do |file_num, file|
      # If no new_script then form is empty and skip
      next if testscripts[file_num][:seq_num].empty? && new_script.nil?

      # Seq_num only exists if it is a file being edited
      if testscripts[file_num][:seq_num].empty?
        # Create new test script file
        filename = new_script.original_filename
        if TestScript.exists?(script_name: filename, assignment: assignment)
          raise I18n.t('automated_tests.duplicate_filename') + filename
        else
          # Override filename from form
          file[:script_name] = filename
          file[:seq_num] = file_num
          updated_script_files[file_num] = file.clone
        end
      else
        # Edit existing test script file
        updated_script_files[file_num] = file.clone
      end

    end

    # Create/Update test support files
    # Ignore editing files for now
    testsupporters.each do |file_num, file|
      # Empty file submission, skip
      next if testsupporters[file_num][:file_name].nil?

      updated_support_files[file_num] = {} || []
      filename = testsupporters[file_num][:file_name].original_filename

      # Create test support file if it does not exist
      if TestSupportFile.exists?(file_name: filename, assignment: assignment)
        raise I18n.t('automated_tests.duplicate_filename') + filename
      else
        updated_support_files[file_num] = file.clone
        # Override filename from form
        updated_support_files[file_num][:file_name] = filename
      end
    end

    # Update test file attributes
    assignment.test_scripts_attributes = updated_script_files
    assignment.test_support_files_attributes = updated_support_files

    # Update assignment enable_test and tokens_per_day attributes
    assignment.enable_test = params[:enable_test]
    assignment.unlimited_tokens = params[:unlimited_tokens]
    num_tokens = params[:tokens_per_day]
    if num_tokens
      assignment.tokens_per_day = num_tokens
    end

    assignment
  end

  # Verify tests can be executed
  def can_run_test?
    if @current_user.admin?
      true
    elsif @current_user.ta?
      true
    elsif @current_user.student?
      # Make sure student belongs to this group
      unless @current_user.accepted_groupings.include?(@grouping)
        return false
      end
      t = @grouping.token
      if t == nil
        raise I18n.t('automated_tests.missing_tokens')
      end
      if t.tokens > 0
        t.decrease_tokens
        true
      else
        false
      end
    end
  end

  # Export group repository for testing
  def export_repository(group, repo_dest_dir)
    # Create the test framework repository
    unless File.exist?(MarkusConfigurator
                           .markus_config_automated_tests_repository)
      FileUtils.mkdir(MarkusConfigurator
                          .markus_config_automated_tests_repository)
    end

    # Delete student's assignment repository if it already exist
    repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, group.repo_name)
    if File.exist?(repo_dir)
      FileUtils.rm_rf(repo_dir)
    end

    return group.repo.export(repo_dest_dir)
  rescue StandardError => e
    return "#{e.message}"
  end

  # Export configuration files for testing
  def export_configuration_files(assignment, group, repo_dest_dir)
    assignment_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.short_identifier)
    repo_assignment_dir = File.join(repo_dest_dir, assignment.short_identifier)

    # Store the Api key of the grader or the admin in the api.txt file in the exported repository
    FileUtils.touch(File.join(assignment_dir, 'api.txt'))
    api_key_file = File.open(File.join(repo_assignment_dir, 'api.txt'), 'w')
    api_key_file.write(current_user.api_key)
    api_key_file.close

    # Create a file "export.properties" where group_name and assignment name are stored for Ant
    FileUtils.touch(File.join(assignment_dir, 'export.properties'))
    api_key_file = File.open(File.join(repo_assignment_dir, 'export.properties'), 'w')
    api_key_file.write('group_name = ' + group.group_name + "\n")
    api_key_file.write('assignment = ' + assignment.short_identifier + "\n")
    api_key_file.close
  end

  # Delete test repository directory
  def delete_test_repo(group, repo_dest_dir)
    repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, group.repo_name)
    # Delete student's assignment repository if it exist
    if File.exist?(repo_dir)
      FileUtils.rm_rf(repo_dir)
    end
  end

  # Copy files needed for testing
  def copy_ant_files(assignment, repo_dest_dir)
    # Check if the repository where you want to copy Ant files to exist
    unless File.exist?(repo_dest_dir)
      raise I18n.t('automated_tests.dir_not_exist', {dir: repo_dest_dir})
    end

    # Create the src repository to put student's files
    assignment_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.short_identifier)
    repo_assignment_dir = File.join(repo_dest_dir, assignment.short_identifier)
    FileUtils.mkdir(File.join(repo_assignment_dir, 'src'))

    # Move student's source files to the src repository
    pwd = FileUtils.pwd
    FileUtils.cd(repo_assignment_dir)
    FileUtils.mv(Dir.glob('*'), File.join(repo_assignment_dir, 'src'),
                 force: true)

    # You always have to come back to your former working directory if you want to avoid errors
    FileUtils.cd(pwd)

    # Copy the build.xml, build.properties Ant Files and api_helpers (only one is needed)
    if File.exist?(assignment_dir)
      FileUtils.cp(File.join(assignment_dir, 'build.xml'), repo_assignment_dir)
      FileUtils.cp(File.join(assignment_dir, 'build.properties'), repo_assignment_dir)
      FileUtils.cp('lib/tools/api_helper.rb', repo_assignment_dir)
      FileUtils.cp('lib/tools/api_helper.py', repo_assignment_dir)

      # Copy the test folder:
      # If the current user is a student, do not copy tests that are marked 'is_private' over
      # Otherwise, copy all tests over
      if @current_user.student?
        # Create the test folder
        assignment_test_dir = File.join(assignment_dir, 'test')
        repo_assignment_test_dir = File.join(repo_assignment_dir, 'test')
        FileUtils.mkdir(repo_assignment_test_dir)
        # Copy all non-private tests over
        assignment.test_files
            .where(filetype: 'test', is_private: 'false')
            .each do |file|
          FileUtils.cp(File.join(assignment_test_dir, file.filename), repo_assignment_test_dir)
        end
      else
        if File.exist?(File.join(assignment_dir, 'test'))
          FileUtils.cp_r(File.join(assignment_dir, 'test'), File.join(repo_assignment_dir, 'test'))
        end
      end

      # Copy the lib folder
      if File.exist?(File.join(assignment_dir, 'lib'))
        FileUtils.cp_r(File.join(assignment_dir, 'lib'), repo_assignment_dir)
      end

      # Copy the parse folder
      if File.exist?(File.join(assignment_dir, 'parse'))
        FileUtils.cp_r(File.join(assignment_dir, 'parse'), repo_assignment_dir)
      end
    else
      raise I18n.t('automated_tests.dir_not_exist', {dir: assignment_dir})
    end
  end

  # Execute Ant which will run the tests against the students' code
  def run_ant_file(result, assignment, repo_dest_dir)
    # Check if the repository where you want to copy Ant files to exist
    unless File.exist?(repo_dest_dir)
      raise I18n.t('automated_tests.dir_not_exist', {dir: repo_dest_dir})
    end

    # Go to the directory where the Ant program must be run
    repo_assignment_dir = File.join(repo_dest_dir, assignment.short_identifier)
    pwd = FileUtils.pwd
    FileUtils.cd(repo_assignment_dir)

    # Execute Ant and log output in a temp logfile
    logfile = 'build_log.xml'
    system ("ant -logger org.apache.tools.ant.DefaultLogger -logfile #{logfile}")

    # Change back to the Rails Working directory
    FileUtils.cd(pwd)

    # File to store build details
    filename = I18n.l(Time.zone.now, format: :ant_date) + '.log'
    # Status of Ant build
    status = ''

    # Handle output depending on if the system command:
    # - executed successfully (ie. Ant returns a BUILD SUCCESSFUL exit(0))
    # - failed (ie. Ant returns a BUILD FAILED exit(1) possibly due to a compilation issue) or
    # - errored out for an unknown reason (ie. Ant returns exit != 0 or 1)
    if $?.exitstatus == 0
      # Build ran succesfully
      status = 'success'
    elsif $?.exitstatus == 1
      # Build failed
      status = 'failed'

      # Go back to the directory where the Ant program must be run
      pwd = FileUtils.pwd
      FileUtils.cd(repo_assignment_dir)

      # Re-run in verbose mode and log issues for diagnosing purposes
      system ("ant -logger org.apache.tools.ant.XmlLogger -logfile #{logfile} -verbose")

      # Change back to the Rails Working directory
      FileUtils.cd(pwd)
    else
      # Otherwise, some other unknown error with Ant has occurred so we simply log
      # the output for problem diagnosing purposes.
      status = 'error'
    end

    # Read in test output logged in build_log.xml
    file = File.open(File.join(repo_assignment_dir, logfile), 'r')
    data = String.new
    file.each_line do |line|
      data += line
    end
    file.close

    # If the build was successful, send output to parser(s)
    if $?.exitstatus == 0
      data = parse_test_output(repo_assignment_dir, assignment, logfile, data)
    end

    # Create TestResult object
    # (Build failures and errors will be logged and stored as well for diagnostic purposes)
    TestResult.create(filename: filename,
                      file_content: data,
                      submission_id: result.submission.id,
                      status: status,
                      user_id: @current_user.id)
  end

  # Send output to parser(s) if any
  def parse_test_output(repo_assignment_dir, assignment, logfile, data)
    # Store test output
    output = data

    # If any test parsers exist, execute Ant's 'parse' target
    if assignment.test_files.find_by_filetype('parse')
      # Go to the directory where the Ant program must be run
      pwd = FileUtils.pwd
      FileUtils.cd(repo_assignment_dir)

      # Run Ant to parse test output
      system ("ant parse -logger org.apache.tools.ant.DefaultLogger -logfile #{logfile} -Doutput=#{data}")

      # Change back to the Rails Working directory
      FileUtils.cd(pwd)

      # Read in test output logged in logfile
      file = File.open(File.join(repo_assignment_dir, logfile), 'r')
      output = String.new
      file.each_line do |line|
        output += line
      end
      file.close
    end

    # Return parsed (or unparsed) test output
    output
  end

  def self.request_a_test_run(grouping_id, call_on, current_user)
    @current_user = current_user
    #@submission = Submission.find(submission_id)
    @grouping = Grouping.find(grouping_id)
    @assignment = @grouping.assignment
    @group = @grouping.group

    @repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @group.repo_name)
    export_group_repo(@group, @repo_dir)

    @list_run_scripts = scripts_to_run(@assignment, call_on)

    async_test_request(grouping_id, call_on)
  end


  # Export group repository for testing. Students' submitted files
  # are stored in the group svn repository. They must be exported
  # before copying to the test server.
  def self.export_group_repo(group, repo_dir)
    # Create the automated test repository
    unless File.exists?(MarkusConfigurator.markus_config_automated_tests_repository)
      FileUtils.mkdir(MarkusConfigurator.markus_config_automated_tests_repository)
    end

    # Delete student's assignment repository if it already exists
    delete_repo(repo_dir)

    # export
    return group.repo.export(repo_dir)
  end

  # Delete student's assignment repository if it already exists
  def self.delete_repo(repo_dir)
    if File.exists?(repo_dir)
      FileUtils.rm_rf(repo_dir)
    end
  end


  # Find the list of test scripts to run the test. Return the list of
  # test scripts in the order specified by seq_num (running order)
  def self.scripts_to_run(assignment, call_on)
    # Find all the test scripts of the current assignment
    all_scripts = TestScript.where(assignment_id: assignment.id)

    list_run_scripts = Array.new

    # If the test run is requested at collection (by Admin or TA),
    # All of the test scripts should be run.
    if call_on == 'collection'
      list_run_scripts = all_scripts
    else
      # If the test run is requested at submission or upon request,
      # verify the script is allowed to run.
      all_scripts.each do |script|
        if call_on == 'submission' && script.run_on_submission
          list_run_scripts.insert(list_run_scripts.length, script)
        elsif call_on == 'request' && script.run_on_request
          list_run_scripts.insert(list_run_scripts.length, script)
        end
      end
    end

    # sort list_run_scripts using ruby's in place sorting method
    list_run_scripts.sort_by! &:seq_num
    list_run_scripts
  end

  # Request an automated test. Ask Resque to enqueue a job.
  def self.async_test_request(grouping_id, call_on)
    if files_available? && has_permission?
      Resque.enqueue(AutomatedTestsHelper, grouping_id, call_on)
    end
  end


  # Verify that MarkUs has some files to run the test.
  # Note: this does not guarantee all required files are presented.
  # Instead, it checks if there is at least one test script and
  # source files are successfully exported.
  def self.files_available?
    test_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @assignment.short_identifier)
    src_dir = @repo_dir
    assign_dir = @repo_dir + '/' + @assignment.repository_folder

    if !(File.exists?(test_dir))
      # TODO: show the error to user instead of raising a runtime error
      raise I18n.t('automated_tests.test_files_unavailable')
    elsif !(File.exists?(src_dir))
      # TODO: show the error to user instead of raising a runtime error
      raise I18n.t('automated_tests.source_files_unavailable')
    end

    if !(File.exists?(assign_dir))
      # TODO: show the error to user instead of raising a runtime error
      raise I18n.t('automated_tests.source_files_unavailable')
    end

    dir_contents = Dir.entries(assign_dir)

    #if there are no files in repo (ie only the current and parent directory pointers)
    if (dir_contents.length <= 2)
      raise I18n.t('automated_tests.source_files_unavailable')
    end

    scripts = TestScript.where(assignment_id: @assignment.id)
    if scripts.empty?
      # TODO: show the error to user instead of raising a runtime error
      raise I18n.t('automated_tests.test_files_unavailable')
    end

    true
  end

  # Verify the user has the permission to run the tests - admin
  # and graders always have the permission, while student has to
  # belong to the group, and have at least one token.
  def self.has_permission?
    if @current_user.admin?
      true
    elsif @current_user.ta?
      true
    elsif @current_user.student?
      # Make sure student belongs to this group
      if not @current_user.accepted_groupings.include?(@grouping)
        # TODO: show the error to user instead of raising a runtime error
        raise I18n.t('automated_tests.not_belong_to_group')
      end
      #can skip checking tokens if we have unlimited
      if @grouping.assignment.unlimited_tokens
        return true
      end
      t = @grouping.token
      if t.nil?
        raise I18n.t('automated_tests.missing_tokens')
      end
      if t.tokens > 0
        t.decrease_tokens
        true
      else
        # TODO: show the error to user instead of raising a runtime error
        raise I18n.t('automated_tests.missing_tokens')
      end
    end
  end


  # Perform a job for automated testing. This code is run by
  # the Resque workers - it should not be called from other functions.
  def self.perform(grouping_id, call_on)
    #@submission = Submission.find(submission_id)
    @grouping = Grouping.find(grouping_id)
    @assignment = @grouping.assignment
    @group = @grouping.group
    @repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @group.repo_name)

    stderr, result, status = launch_test(@assignment, @repo_dir, call_on)

    if !status
      #for debugging any errors in launch_test
      assignment = @assignment
      repo_dir = @repo_dir
      m_logger = MarkusLogger.instance


      src_dir = File.join(repo_dir, assignment.repository_folder)

      # Get test_dir
      test_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.repository_folder)

      # Get the name of the test server
      server = 'localhost'

      # Get the directory and name of the test runner script
      test_runner = MarkusConfigurator.markus_ate_test_runner_script_name

      # Get the test run directory of the files
      run_dir = MarkusConfigurator.markus_ate_test_run_directory


      m_logger.log("error with launching test, error: #{stderr} and status: #{status}\n src_dir: #{src_dir}\ntest_dir: #{test_dir}\nserver: #{server}\ntest_runner: #{test_runner}\nrun_dir: #{run_dir}",MarkusLogger::ERROR)

      # TODO: handle this error better
      raise 'error'
    else
      process_result(result)
    end

  end

  # Launch the test on the test server by scp files to the server
  # and run the script.
  # This function returns three values:
  # stderr
  # stdout
  # boolean indicating whether execution suceeeded
  def self.launch_test(assignment, repo_path, call_on)
    submission_path = File.join(repo_path, assignment.repository_folder)
    assignment_tests_path = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.repository_folder)

    test_harness_path = MarkusConfigurator.markus_ate_test_runner_script_name

    # Where to run the tests
    test_box_path = MarkusConfigurator.markus_ate_test_run_directory

    # Create clean folder to execute tests
    stdout, stderr, status = Open3.capture3("rm -rf #{test_box_path} && "\
      "mkdir #{test_box_path}")
    unless status.success?
      return [stderr, stdout, status]
    end

    # Securely copy student's submission, test files and test harness script to test_box_path
    stdout, stderr, status = Open3.capture3("cp -r '#{submission_path}'/* "\
      "#{test_box_path}")
    unless status.success?
      return [stderr, stdout, status]
    end

    stdout, stderr, status = Open3.capture3("cp -r '#{assignment_tests_path}'/* "\
      "#{test_box_path}")
    unless status.success?
      return [stderr, stdout, status]
    end

    stdout, stderr, status = Open3.capture3("cp -r #{test_harness_path} "\
      "#{test_box_path}")
    unless status.success?
      return [stderr, stdout, status]
    end

    # Find the test scripts for this test run, and parse the argument list
    list_run_scripts = scripts_to_run(assignment, call_on)
    arg_list = ''
    list_run_scripts.each do |script|
      arg_list = arg_list + "#{script.script_name.gsub(/\s/, "\\ ")} #{script.halts_testing} "
    end

    # Run script
    test_harness_name = File.basename(test_harness_path)
    stdout, stderr, status = Open3.capture3("cd #{test_box_path}; "\
      "ruby #{test_harness_name} #{arg_list}")

    if !(status.success?)
      return [stderr, stdout, false]
    else
      test_results_path = "#{AUTOMATED_TESTS_REPOSITORY}/test_runs/test_run_#{Time.now.to_i}"
      FileUtils.mkdir_p(test_results_path)
      File.write("#{test_results_path}/output.txt", stdout)
      File.write("#{test_results_path}/error.txt", stderr)
      return [stdout, stdout, true]
    end
  end

  def self.process_result(raw_result)
    result = Hash.from_xml(raw_result)
    repo = @grouping.group.repo
    revision = repo.get_latest_revision
    revision_number = revision.revision_number
    raw_test_scripts = result['testrun']['test_script']

    # Hash.from_xml will yield a hash if only one test script
    # and an array otherwise
    if raw_test_scripts.nil?
      return
    elsif raw_test_scripts.is_a?(Array)
      test_scripts = raw_test_scripts
    else
      test_scripts = [raw_test_scripts]
    end

    # For now, we just use the first test script for the association
    raw_test_script = test_scripts.first
    script_name = raw_test_script['script_name']
    test_script = TestScript.find_by(assignment_id: @assignment.id,
                                     script_name: script_name)

    completion_status = 'pass'
    marks_earned = 0
    test_scripts.each do |script|
      tests = script['test']
      tests.each do |test|
        marks_earned += test['marks_earned'].to_i
        # if any of the tests fail, we consider the completion status to be fail
        completion_status = 'fail' if test['status'] != 'pass'
      end
    end

    # TODO: HACK. Do we always need a submission id?
    submission_id = Submission.last.id
    TestResult.create(grouping_id: @grouping.id,
                      test_script_id: test_script.id,
                      name: script_name,
                      repo_revision: revision_number,
                      input_description: '',
                      actual_output: result.to_json,
                      expected_output: '',
                      submission_id: submission_id,
                      marks_earned: marks_earned,
                      completion_status: completion_status)
  end
end

#test-framework version
# require 'libxml'
# require 'open3'

# # Helper methods for Testing Framework forms
# module AutomatedTestsHelper

#   include LibXML

#   # This is the waiting list for automated testing. Once a test is requested,
#   # it is enqueued and it is waiting for execution. Resque manages this queue.
#   @queue = :test_waiting_list

#   # This is the calling interface to request a test run.
#   def AutomatedTestsHelper.request_a_test_run(grouping_id, call_on, current_user)
#     @current_user = current_user
#     #@submission = Submission.find(submission_id)
#     @grouping = Grouping.find(grouping_id)
#     @assignment = @grouping.assignment
#     @group = @grouping.group

#     @repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @group.repo_name)
#     export_group_repo(@group, @repo_dir)

#     @list_run_scripts = scripts_to_run(@assignment, call_on)

#     async_test_request(grouping_id, call_on)
#   end

#   # Delete repository directory
#   def self.delete_repo(repo_dir)
#     # Delete student's assignment repository if it already exists
#     if File.exists?(repo_dir)
#       FileUtils.rm_rf(repo_dir)
#     end
#   end

#   # Export group repository for testing. Students' submitted files
#   # are stored in the group svn repository. They must be exported
#   # before copying to the test server.
#   def self.export_group_repo(group, repo_dir)
#     # Create the automated test repository
#     if !(File.exists?(MarkusConfigurator.
#             markus_config_automated_tests_repository))
#       FileUtils.mkdir(MarkusConfigurator.markus_config_automated_tests_repository)
#     end

#     # Delete student's assignment repository if it already exists
#     delete_repo(repo_dir)

#     # export
#     return group.repo.export(repo_dir)
#     rescue Exception => e
#       return "#{e.message}"
#   end

#   # Find the list of test scripts to run the test. Return the list of
#   # test scripts in the order specified by seq_num (running order)
#   def self.scripts_to_run(assignment, call_on)
#     # Find all the test scripts of the current assignment
#     all_scripts = TestScript.find_all_by_assignment_id(assignment.id)

#     list_run_scripts = Array.new

#     # If the test run is requested at collection (by Admin or TA),
#     # All of the test scripts should be run.
#     if call_on == "collection"
#       list_run_scripts = all_scripts
#     else
#       # If the test run is requested at submission or upon request,
#       # verify the script is allowed to run.
#       all_scripts.each do |script|
#         if (call_on == "submission") && script.run_on_submission
#           list_run_scripts.insert(list_run_scripts.length, script)
#         elsif (call_on == "request") && script.run_on_request
#           list_run_scripts.insert(list_run_scripts.length, script)
#         end
#       end
#     end

#     # sort list_run_scripts using ruby's in place sorting method
#     list_run_scripts.sort_by! {|script| script.seq_num}

#     # list_run_scripts should be sorted now. Perform a check here.
#     # Take this out if it causes performance issue.
#     ctr = 0
#     while ctr < list_run_scripts.length - 1
#       if (list_run_scripts[ctr].seq_num) > (list_run_scripts[ctr+1].seq_num)
#         raise "list_run_scripts is not sorted"
#       end
#       ctr = ctr + 1
#     end

#     return list_run_scripts
#   end

#   # Request an automated test. Ask Resque to enqueue a job.
#   def self.async_test_request(grouping_id, call_on)
#     if files_available?
#       if has_permission?
#         Resque.enqueue(AutomatedTestsHelper, grouping_id, call_on)
#       end
#     end
#   end

#   # Verify the user has the permission to run the tests - admin
#   # and graders always have the permission, while student has to
#   # belong to the group, and have at least one token.
#   def self.has_permission?()
#     if @current_user.admin?
#       true
#     elsif @current_user.ta?
#       true
#     elsif @current_user.student?
#       # Make sure student belongs to this group
#       if not @current_user.accepted_groupings.include?(@grouping)
#         # TODO: show the error to user instead of raising a runtime error
#         raise I18n.t("automated_tests.not_belong_to_group")
#       end
#       #can skip checking tokens if we have unlimited
#       if @grouping.assignment.unlimited_tokens
#         return true
#       end
#       t = @grouping.token
#       if t == nil
#         raise I18n.t('automated_tests.missing_tokens')
#       end
#       if t.tokens > 0
#         t.decrease_tokens
#         true
#       else
#         # TODO: show the error to user instead of raising a runtime error
#         raise I18n.t("automated_tests.missing_tokens")
#       end
#     end
#   end

#   # Verify that MarkUs has some files to run the test.
#   # Note: this does not guarantee all required files are presented.
#   # Instead, it checks if there is at least one test script and
#   # source files are successfully exported.
#   def self.files_available?()
#     test_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @assignment.short_identifier)
#     src_dir = @repo_dir
#     assign_dir = @repo_dir + "/" + @assignment.repository_folder

#     if !(File.exists?(test_dir))
#       # TODO: show the error to user instead of raising a runtime error
#       raise I18n.t("automated_tests.test_files_unavailable")
#     elsif !(File.exists?(src_dir))
#       # TODO: show the error to user instead of raising a runtime error
#       raise I18n.t("automated_tests.source_files_unavailable")
#     end

#     if !(File.exists?(assign_dir))
#       # TODO: show the error to user instead of raising a runtime error
#       raise I18n.t("automated_tests.source_files_unavailable")
#     end

#     dir_contents = Dir.entries(assign_dir)

#     #if there are no files in repo (ie only the current and parent directory pointers)
#     if (dir_contents.length <= 2)
#       raise I18n.t("automated_tests.source_files_unavailable")
#     end

#     scripts = TestScript.find_all_by_assignment_id(@assignment.id)
#     if scripts.empty?
#       # TODO: show the error to user instead of raising a runtime error
#       raise I18n.t("automated_tests.test_files_unavailable")
#     end

#     return true
#   end

#   # Perform a job for automated testing. This code is run by
#   # the Resque workers - it should not be called from other functions.
#   def self.perform(grouping_id, call_on)
#     # Pick a server, launch the Test Runner and wait for the result
#     # Then store the result into the database

#     #@submission = Submission.find(submission_id)
#     @grouping = Grouping.find(grouping_id)
#     @assignment = @grouping.assignment
#     @group = @grouping.group
#     @repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @group.repo_name)

#     @list_of_servers = MarkusConfigurator.markus_ate_test_server_hosts.split(' ')

#     while true
#       @test_server_id = choose_test_server()
#       if @test_server_id >= 0
#         break
#       else
#         sleep 5               # if no server is available, sleep for 5 second before it checks again
#       end
#     end

#     result, status = launch_test(@test_server_id, @assignment, @repo_dir, call_on)

#     if !status
#       # TODO: handle this error better
#       raise "error"
#     else
#       process_result(result, grouping_id, @assignment.id)
#     end

#   end

#   # From a list of test servers, choose the next available server
#   # using round-robin. Return the id of the server, and return -1
#   # if no server is available.
#   # TODO: keep track of the max num of tests running on a server
#   def self.choose_test_server()

#     if (defined? @last_server) && MarkusConfigurator.automated_testing_engine_on?
#       # find the index of the last server, and return the next index
#       @last_server = (@last_server + 1) % MarkusConfigurator.markus_ate_num_test_servers
#     else
#       @last_server = 0
#     end

#     return @last_server

#   end

#   # Launch the test on the test server by scp files to the server
#   # and run the script.
#   # This function returns two values: first one is the output from
#   # stdout or stderr, depending on whether the execution passed or
#   # had error; the second one is a boolean variable, true => execution
#   # passeed, false => error occurred.
#   def self.launch_test(server_id, assignment, repo_dir, call_on)
#     # Get src_dir
#     src_dir = File.join(repo_dir, assignment.repository_folder)

#     # Get test_dir
#     test_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.repository_folder)

#     # Get the name of the test server
#     server = @list_of_servers[server_id]

#     # Get the directory and name of the test runner script
#     test_runner = MarkusConfigurator.markus_ate_test_runner_script_name

#     # Get the test run directory of the files
#     run_dir = MarkusConfigurator.markus_ate_test_run_directory

#     # Delete the test run directory to remove files from previous test
#     stdout, stderr, status = Open3.capture3("ssh #{server} rm -rf #{run_dir}")
#     if !(status.success?)
#       return [stderr, false]
#     end

#     # Recreate the test run directory
#     stdout, stderr, status = Open3.capture3("ssh #{server} mkdir #{run_dir}")
#     if !(status.success?)
#       return [stderr, false]
#     end

#     # Securely copy source files, test files and test runner script to run_dir
#     stdout, stderr, status = Open3.capture3("scp -p -r '#{src_dir}'/* #{server}:#{run_dir}")
#     if !(status.success?)
#       return [stderr, false]
#     end
#     stdout, stderr, status = Open3.capture3("scp -p -r '#{test_dir}'/* #{server}:#{run_dir}")
#     if !(status.success?)
#       return [stderr, false]
#     end
#     stdout, stderr, status = Open3.capture3("ssh #{server} cp #{test_runner} #{run_dir}")
#     if !(status.success?)
#       return [stderr, false]
#     end

#     # Find the test scripts for this test run, and parse the argument list
#     list_run_scripts = scripts_to_run(assignment, call_on)
#     arg_list = ""
#     list_run_scripts.each do |script|
#       arg_list = arg_list + "#{script.script_name.gsub(/\s/, "\\ ")} #{script.halts_testing} "
#     end

#     # Run script
#     test_runner_name = File.basename(test_runner)
#     stdout, stderr, status = Open3.capture3("ssh #{server} \"cd #{run_dir}; ruby #{test_runner_name} #{arg_list}\"")
#     if !(status.success?)
#       return [stderr, false]
#     else
#       return [stdout, true]
#     end

#   end

#   def self.process_result(result, grouping_id, assignment_id)
#     parser = XML::Parser.string(result)

#     # parse the xml doc
#     doc = parser.parse

#     @grouping = Grouping.find(grouping_id)

#     repo = @grouping.group.repo
#     @revision  = repo.get_latest_revision
#     @revision_number = @revision.revision_number

#     # find all the test_script nodes and loop over them
#     test_scripts = doc.find('/testrun/test_script')
#     test_scripts.each do |s_node|
#       script_result = TestScriptResult.new
#       script_result.grouping_id = grouping_id
#       script_marks_earned = 0    # cumulate the marks_earn in this script

#       # find the script name and save it
#       script_name_nodes = s_node.find('./script_name')
#       if script_name_nodes.length != 1
#         # FIXME: better error message is required (use locale)
#         raise "None or more than one test script name is found in one test_script tag."
#       else
#         script_name = script_name_nodes[0].content
#       end

#       # Find all the test scripts with this script_name.
#       # There should be one and only one record - raise exception if not
#       test_script_array = TestScript.find_all_by_assignment_id_and_script_name(assignment_id, script_name)
#       if test_script_array.length != 1
#         # FIXME: better error message is required (use locale)
#         raise "None or more than one test script is found for script name " + script_name
#       else
#         test_script = test_script_array[0]
#       end

#       script_result.test_script_id = test_script.id

#       script_marks_earned_nodes = s_node.find('./marks_earned')
#       script_result.marks_earned = script_marks_earned_nodes[0].content.to_i

#       script_result.repo_revision = @revision_number

#       # save to database
#       script_result.save

#       # find all the test nodes and loop over them
#       tests = s_node.find('./test')
#       tests.each do |t_node|
#         test_result = TestResult.new
#         test_result.grouping_id = grouping_id
#         test_result.test_script_id = test_script.id
#         # give default values
#         test_result.name = 'no name is given'
#         test_result.completion_status = 'error'
#         test_result.input_description = ''
#         test_result.expected_output = ''
#         test_result.actual_output = ''
#         test_result.marks_earned = 0

#         t_node.each_element do |child|
#           if child.name == 'name'
#             test_result.name = child.content
#           elsif child.name == 'status'
#             test_result.completion_status = child.content.downcase
#           elsif child.name == 'input'
#             test_result.input_description = child.content
#           elsif child.name == 'expected'
#             test_result.expected_output = child.content
#           elsif child.name == 'actual'
#             test_result.actual_output = child.content
#           elsif child.name == 'marks_earned'
#             test_result.marks_earned = child.content
#             script_marks_earned += child.content.to_i
#           else
#             # FIXME: better error message is required (use locale)
#             raise "Error: malformed xml from test runner. Unclaimed tag: " + child.name
#           end
#         end

#         test_result.repo_revision = @revision_number

#         test_result.test_script_result_id = script_result.id

#         # save to database
#         test_result.save
#       end

#       # if a marks_earned tag exists under test_script tag, get the value;
#       # otherwise, use the cumulative marks earned from all unit tests
#       script_marks_earned_nodes = s_node.find('./marks_earned')
#       if script_marks_earned_nodes.length == 1
#         script_result.marks_earned = script_marks_earned_nodes[0].content.to_i

#         script_result.save
#       end

#     end
#   end

#   # Create a repository for the test scripts, and a placeholder script
#   def create_test_scripts(assignment)

#     # Setup Testing Framework repository
#     test_dir = File.join(
#                 MarkusConfigurator.markus_config_automated_tests_repository,
#                 assignment.short_identifier)
#     FileUtils.makedirs(test_dir)

#     assignment.reload
#   end
#
#   def add_test_script_link(name, form)
#     link_to_function name do |page|
#       new_test_script = TestScript.new
#       test_script = render(:partial => 'test_script_upload',
#                          :locals => {:form => form,
#                                      :test_script => new_test_script})

#       test_script_options = render(:partial => 'test_script_options',
#                          :locals => {:form => form,
#                                      :test_script => new_test_script })
#       page << %{
#         if ($F('is_testing_framework_enabled') != null) {
#           var new_test_script_id = new Date().getTime();
#           var last_seqnum = jQuery('.seqnum').last().val();
#           var new_seqnum = 0;
#           if(last_seqnum) {
#             new_seqnum = 16 + parseFloat(last_seqnum);
#           }

#           var new_test_script = jQuery("#{ escape_javascript test_script}".replace(/(attributes_\\d+|\\[\\d+\\])/g, new_test_script_id));
#           jQuery('#test_scripts').append(new_test_script);

#           new_test_script.find('.seqnum').val(new_seqnum);
#           new_test_script.data('collapsed', false);

#           new_test_script.find('.upload_file').change(function () {
#             new_test_script.find('.file_name').text(this.value);
#           })
#         } else {
#           alert("#{I18n.t("automated_tests.add_test_script_file_alert")}");
#         }
#       }
#     end
#   end

# end

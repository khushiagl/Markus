class GroupingPolicy < ApplicationPolicy

  def run_tests?
    check?(:run_tests?, record.assignment) && (!user.student? ||
      (check?(:member?) && check?(:not_in_progress?) && check?(:tokens_available?))
    )
  end

  def member?
    record.accepted_students.include?(user)
  end

  def not_in_progress?
    !record.student_test_run_in_progress?
  end

  def tokens_available?
    record.test_tokens > 0 || record.assignment.unlimited_tokens
  end

  # Policies for group invitations.
  def invite_member?
    allowed_to?(:students_form_groups?) &&
    allowed_to?(:before_due_date?)
  end

  def students_form_groups?
    !record.assignment.invalid_override
  end

  def before_due_date?
    !record.assignment.past_collection_date?(record.inviter.section)
  end

  def delete_rejected?
    user.user_name == record.inviter.user_name
  end
end

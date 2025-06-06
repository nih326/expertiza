require 'rails_helper'
describe ReviewMappingController do
  let(:assignment) { double('Assignment', id: 1) }
  let(:reviewer) { double('Participant', id: 1, name: 'reviewer') }
  let(:review_response_map) do
    double('ReviewResponseMap', id: 1, map_id: 1, assignment: assignment,
                                reviewer: reviewer, reviewee: double('Participant', id: 2, name: 'reviewee'))
  end
  let(:metareview_response_map) do
    double('MetareviewResponseMap', id: 1, map_id: 1, assignment: assignment,
                                    reviewer: reviewer, reviewee: double('Participant', id: 2, name: 'reviewee'))
  end
  let(:participant) { double('AssignmentParticipant', id: 1, can_review: false, user: double('User', id: 1)) }
  let(:participant1) { double('AssignmentParticipant', id: 2, can_review: true, user: double('User', id: 2)) }
  let(:user) { double('User', id: 3) }
  let(:participant2) { double('AssignmentParticipant', id: 3, can_review: true, user: user) }
  let(:team) { double('AssignmentTeam', name: 'no one') }
  let(:team1) { double('AssignmentTeam', name: 'no one1') }

  before(:each) do
    allow(Assignment).to receive(:find).with('1').and_return(assignment)
    instructor = build(:instructor)
    stub_current_user(instructor, instructor.role.name, instructor.role)
    allow(participant).to receive(:get_reviewer).and_return(participant)
    allow(participant1).to receive(:get_reviewer).and_return(participant1)
    allow(participant2).to receive(:get_reviewer).and_return(participant2)
    allow(reviewer).to receive(:get_reviewer).and_return(reviewer)
  end

  describe '#add_calibration' do
    context 'when both participant and review_response_map have already existed' do
      it 'does not need to create new objects and redirects to responses#new maps' do
        allow(AssignmentParticipant).to receive_message_chain(:where, :first)
          .with(parent_id: '1', user_id: 1).with(no_args).and_return(participant)
        allow(ReviewResponseMap).to receive_message_chain(:where, :first)
          .with(reviewed_object_id: '1', reviewer_id: 1, reviewee_id: '1', calibrate_to: true).with(no_args).and_return(review_response_map)
        request_params = { id: 1, team_id: 1 }
        user_session = { user: build(:instructor, id: 1) }
        get :add_calibration, params: request_params, session: user_session
        expect(response).to redirect_to '/response/new?assignment_id=1&id=1&return=assignment_edit'
      end
    end

    context 'when both participant and review_response_map have not been created' do
      it 'creates new objects and redirects to responses#new maps' do
        allow(AssignmentParticipant).to receive_message_chain(:where, :first)
          .with(parent_id: '1', user_id: 1).with(no_args).and_return(nil)
        allow(AssignmentParticipant).to receive(:create)
          .with(parent_id: '1', user_id: 1, can_submit: 1, can_review: 1, can_take_quiz: 1, handle: 'handle').and_return(participant)
        allow(ReviewResponseMap).to receive_message_chain(:where, :first)
          .with(reviewed_object_id: '1', reviewer_id: 1, reviewee_id: '1', calibrate_to: true).with(no_args).and_return(nil)
        allow(ReviewResponseMap).to receive(:create)
          .with(reviewed_object_id: '1', reviewer_id: 1, reviewee_id: '1', calibrate_to: true).and_return(review_response_map)
        request_params = { id: 1, team_id: 1 }
        user_session = { user: build(:instructor, id: 1) }
        get :add_calibration, params: request_params, session: user_session
        expect(response).to redirect_to '/response/new?assignment_id=1&id=1&return=assignment_edit'
      end
    end
  end

  describe '#add_reviewer and #get_reviewer' do
    before(:each) do
      allow(User).to receive_message_chain(:where, :first).with(name: 'expertiza').with(no_args).and_return(double('User', id: 1))
      @params = {
        id: 1,
        topic_id: 1,
        user: { name: 'expertiza' },
        contributor_id: 1
      }
    end

    context 'when team_user does not exist' do
      it 'shows an error message and redirects to review_mapping#list_mappings page' do
        allow(TeamsUser).to receive(:exists?).with(team_id: '1', user_id: 1).and_return(true)
        post :add_reviewer, params: @params
        expect(response).to redirect_to '/review_mapping/list_mappings?id=1'
      end
    end

    context 'when team_user exists and get_reviewer method returns a reviewer' do
      it 'creates a whole bunch of objects and redirects to review_mapping#list_mappings page' do
        allow(TeamsUser).to receive(:exists?).with(team_id: '1', user_id: 1).and_return(false)
        allow(SignUpSheet).to receive(:signup_team).with(1, 1, '1').and_return(true)
        user = double('User', id: 1)
        allow(User).to receive(:from_params).with(any_args).and_return(user)
        allow(AssignmentParticipant).to receive(:where).with(user_id: 1, parent_id: 1)
                                                       .and_return([reviewer])
        allow(ReviewResponseMap).to receive_message_chain(:where, :first)
          .with(reviewee_id: '1', reviewer_id: 1).with(no_args).and_return(nil)
        allow(ReviewResponseMap).to receive(:create).with(reviewee_id: '1', reviewer_id: 1, reviewed_object_id: 1).and_return(nil)
        post :add_reviewer, params: @params
        expect(response).to redirect_to '/review_mapping/list_mappings?id=1&msg='
      end
    end

    context 'when instructor tries to assign a student their own artifact for reviewing' do
      it 'flashes an error message' do
        allow(TeamsUser).to receive(:exists?).with(team_id: '1', user_id: 1).and_return(true)
        post :add_reviewer, params: @params
        expect(flash[:error]).to eq('You cannot assign this student to review his/her own artifact.')
        expect(response).to redirect_to '/review_mapping/list_mappings?id=1'
      end
    end
  end

  describe '#assign_reviewer_dynamically' do
    before(:each) do
      allow(AssignmentParticipant).to receive_message_chain(:where, :first)
        .with(user_id: '1', parent_id: 1).with(no_args).and_return(participant)
    end

    context 'when assignment has topics and no topic is selected by reviewer' do
      it 'shows an error message and redirects to student_review#list page' do
        allow(assignment).to receive(:topics?).and_return(true)
        allow(assignment).to receive(:can_choose_topic_to_review?).and_return(true)
        request_params = {
          assignment_id: 1,
          reviewer_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(flash[:error]).to eq('No topic is selected.  Please go back and select a topic.')
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end

    context 'when assignment has topics and a topic is selected by reviewer' do
      it 'assigns reviewer dynamically and redirects to student_review#list page' do
        allow(assignment).to receive(:topics?).and_return(true)
        topic = double('SignUpTopic')
        allow(SignUpTopic).to receive(:find).with('1').and_return(topic)
        allow(assignment).to receive(:assign_reviewer_dynamically).with(participant, topic).and_return(true)
        allow(ReviewResponseMap).to receive(:reviewer_id).with(1).and_return(0)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end

    context 'when assignment does not have topics' do
      it 'runs another algorithms and redirects to student_review#list page' do
        allow(assignment).to receive(:topics?).and_return(false)
        allow(participant).to receive(:set_current_user)
        team1 = double('AssignmentTeam')
        team2 = double('AssignmentTeam')
        teams = [team1, team2]
        allow(assignment).to receive(:candidate_assignment_teams_to_review).with(participant).and_return(teams)
        allow(teams).to receive_message_chain(:to_a, :sample).and_return(team2)
        allow(assignment).to receive(:assign_reviewer_dynamically_no_topic).with(participant, team2).and_return(true)
        allow(ReviewResponseMap).to receive(:reviewer_id).with(1).and_return(0)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end

    context 'when number of reviews are less than the assignment policy' do
      it 'redirects to student review page' do
        allow(assignment).to receive(:topics?).and_return(true)
        topic = double('SignUpTopic')
        allow(SignUpTopic).to receive(:find).with('1').and_return(topic)
        allow(ReviewResponseMap).to receive(:where).with(reviewer_id: 1, reviewed_object_id: 1)
                                                   .and_return([])
        allow(assignment).to receive(:assign_reviewer_dynamically).with(participant, topic).and_return(true)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end

    context 'when number of reviews are greater than the assignment policy' do
      it 'shows a flash error and redirects to student review page' do
        allow(assignment).to receive(:topics?).and_return(true)
        topic = double('SignUpTopic')
        allow(SignUpTopic).to receive(:find).with('1').and_return(topic)
        allow(ReviewResponseMap).to receive(:where).with(reviewer_id: 1, reviewed_object_id: 1)
                                                   .and_return([1, 2, 3])
        allow(assignment).to receive(:assign_reviewer_dynamically).with(participant, topic).and_return(true)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(response).to redirect_to '/student_review/list?id=1'
        expect(flash[:error]).to be_present
      end
    end

    context 'when user has outstanding reviews less than assignment policy' do
      it 'redirects to student review page' do
        allow(assignment).to receive(:topics?).and_return(true)
        topic = double('SignUpTopic')
        allow(SignUpTopic).to receive(:find).with('1').and_return(topic)
        allow(ReviewResponseMap).to receive(:where).with(reviewer_id: 1, reviewed_object_id: 1)
                                                   .and_return(:review_response_map)
        allow(assignment).to receive(:assign_reviewer_dynamically).with(participant, topic).and_return(true)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        allow(assignment).to receive(:max_outstanding_reviews).and_return(0)

        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end

    context 'when user has outstanding reviews greater than assignment policy' do
      it 'redirects to student review page and shows flash error' do
        allow(assignment).to receive(:topics?).and_return(true)
        topic = double('SignUpTopic')
        allow(SignUpTopic).to receive(:find).with('1').and_return(topic)
        allow(ReviewResponseMap).to receive(:where).with(reviewer_id: 1, reviewed_object_id: 1)
                                                   .and_return(:review_response_map)
        allow(assignment).to receive(:assign_reviewer_dynamically).with(participant, topic).and_return(true)
        allow(assignment).to receive(:num_reviews_allowed).and_return(1)
        allow(assignment).to receive(:max_outstanding_reviews).and_return(3)

        request_params = {
          assignment_id: 1,
          reviewer_id: 1,
          topic_id: 1
        }
        post :assign_reviewer_dynamically, params: request_params
        expect(flash[:error]).to be_present
        expect(response).to redirect_to '/student_review/list?id=1'
      end
    end
  end

  # modified test
  describe '#assign_quiz_dynamically' do
    before(:each) do
      allow(AssignmentParticipant).to receive_message_chain(:where, :first)
        .with(user_id: '1', parent_id: 1).with(no_args).and_return(participant)
      @params = {
        assignment_id: 1,
        reviewer_id: 1,
        questionnaire_id: 1,
        participant_id: 1
      }
    end

    context 'when participant is not found' do
      it 'flashes an error and redirects to student_quizzes page' do
        allow(AssignmentParticipant).to receive(:find_by).with(user_id: '1', parent_id: 1).and_return(nil)
        post :assign_quiz_dynamically, params: @params
        expect(flash[:error]).to eq('Participant not registered for this assignment')
        expect(response).to redirect_to('/student_quizzes?id=1')
      end
    end

    context 'when participant has already taken the quiz' do
      it 'flashes an error and redirects to student_quizzes page' do
        allow(AssignmentParticipant).to receive(:find_by).with(user_id: '1', parent_id: 1).and_return(participant)
        allow(QuizResponseMap).to receive(:exists?).and_return(true)
        post :assign_quiz_dynamically, params: @params
        expect(flash[:error]).to eq('Already taken this quiz')
        expect(response).to redirect_to('/student_quizzes?id=1')
      end
    end

    context 'when quiz assignment is successfully created' do
      let(:questionnaire) { double('Questionnaire', id: 1, instructor_id: 1) }
    
      it 'flashes a success message and redirects to student_quizzes page' do
        allow(AssignmentParticipant).to receive(:find_by).with(user_id: '1', parent_id: 1).and_return(participant)
        
        allow(QuizResponseMap).to receive(:exists?).and_return(false)
        
        allow(Questionnaire).to receive(:find).with(1).and_return(questionnaire)
        allow(Questionnaire).to receive(:find).with("1").and_return(questionnaire) 
        
        allow(QuizResponseMap).to receive(:create!).and_return(true)
        
        post :assign_quiz_dynamically, params: @params
        
        expect(flash[:success]).to eq('Quiz successfully assigned')
        expect(response).to redirect_to('/student_quizzes?id=1')
      end
    end

    context 'when quiz assignment creation fails' do
      it 'flashes an error and redirects to student_quizzes page' do
        allow(AssignmentParticipant).to receive(:find_by).with(user_id: '1', parent_id: 1).and_return(participant)
        allow(QuizResponseMap).to receive(:exists?).and_return(false)
        allow(QuizResponseMap).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(QuizResponseMap.new))
        post :assign_quiz_dynamically, params: @params
        expect(flash[:error]).to be_present
        expect(response).to redirect_to('/student_quizzes?id=1')
      end
    end
  end

  describe '#add_metareviewer' do
    let(:context) { create(:metareview_test_context) }
    let(:assignment) { context[:assignment] }
    let(:review_mapping) { context[:review_mapping] }
    let(:reviewer_user) { context[:reviewer_user] }

    context 'successful assignment' do
      it 'creates metareview mapping' do
        expect {
          post :add_metareviewer, params: { 
            id: review_mapping.id,
            user: { name: reviewer_user.name }
          }
        }.to change(MetareviewResponseMap, :count).by(1)
    
        expect(response).to redirect_to(
          action: :list_mappings,
          id: assignment.id,
          msg: ''
        )
      end
    end
    
    context 'duplicate assignment' do
      before do
        create(:meta_review_response_map,
              reviewed_object_id: review_mapping.id,
              reviewer: Participant.find_by(user: reviewer_user))
      end
    
      it 'rejects duplicate assignment' do
        expect {
          post :add_metareviewer, params: { 
            id: review_mapping.id,
            user: { name: reviewer_user.name }
          }
        }.not_to change(MetareviewResponseMap, :count)
    
        expect(response).to redirect_to(
          action: :list_mappings,
          id: assignment.id,
          msg: 'Metareviewer already assigned'
        )
      end
    end
    
    context 'when user not registered' do
      it 'handles unregistered user' do
        unregistered_user = create(:student)
        allow_any_instance_of(ReviewMappingController).to receive(:get_reviewer)
          .and_raise(ActiveRecord::RecordNotFound.new('Participant'))
    
        post :add_metareviewer, params: {
          id: review_mapping.id,
          user: { name: unregistered_user.name }
        }
    
        expect(response).to redirect_to(
          action: :list_mappings,
          id: assignment.id,
          msg: 'Registration error: Participant'
        )
      end
    end
  end

  describe '#assign_metareviewer_dynamically' do
    it 'redirects to student_review#list page' do
      metareviewer = double('AssignmentParticipant', id: 1)
      allow(AssignmentParticipant).to receive(:where).with(user_id: '1', parent_id: 1).and_return([metareviewer])
      allow(assignment).to receive(:assign_metareviewer_dynamically).with(metareviewer).and_return(true)
      request_params = {
        assignment_id: 1,
        metareviewer_id: 1
      }
      post :assign_metareviewer_dynamically, params: request_params
      expect(response).to redirect_to('/student_review/list?id=1')
    end
  end

  describe '#delete_outstanding_reviewers' do
    before(:each) do
      allow(AssignmentTeam).to receive(:find).with('1').and_return(team)
      allow(team).to receive(:review_mappings).and_return([double('ReviewResponseMap', id: 1)])
    end

    context 'when review response map has corresponding responses' do
      it 'shows a flash error and redirects to review_mapping#list_mappings page' do
        allow(Response).to receive(:exists?).with(map_id: 1).and_return(true)
        request_params = {
          id: 1,
          contributor_id: 1
        }
        post :delete_outstanding_reviewers, params: request_params
        expect(flash[:success]).to be nil
        expect(flash[:error]).to eq('1 reviewer(s) cannot be deleted because they have already started a review.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end

    context 'when review response map does not have corresponding responses' do
      it 'shows a flash success and redirects to review_mapping#list_mappings page' do
        allow(Response).to receive(:exists?).with(map_id: 1).and_return(false)
        review_response_map = double('ReviewResponseMap')
        allow(ReviewResponseMap).to receive(:find).with(1).and_return(review_response_map)
        allow(review_response_map).to receive(:destroy).and_return(true)
        request_params = {
          id: 1,
          contributor_id: 1
        }
        post :delete_outstanding_reviewers, params: request_params
        expect(flash[:error]).to be nil
        expect(flash[:success]).to eq('All review mappings for "no one" have been deleted.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
  end

  describe '#delete_all_metareviewers' do
    before(:each) do
      allow(ResponseMap).to receive(:find).with('1').and_return(review_response_map)
      @metareview_response_maps = [metareview_response_map]
      allow(MetareviewResponseMap).to receive(:where).with(reviewed_object_id: 1).and_return(@metareview_response_maps)
    end

    context 'when failed times are bigger than 0' do
      it 'shows an error flash message and redirects to review_mapping#list_mappings page' do
        @metareview_response_maps.each do |metareview_response_map|
          allow(metareview_response_map).to receive(:delete).with(true).and_raise('Boom')
        end
        request_params = { id: 1, force: true }
        post :delete_all_metareviewers, params: request_params
        expect(flash[:note]).to be nil
        expect(flash[:error]).to eq('A delete action failed:<br/>1 metareviews exist for these mappings. '\
          "Delete these mappings anyway?&nbsp;<a href='http://test.host/review_mapping/delete_all_metareviewers?force=1&id=1'>Yes</a>&nbsp;|&nbsp;"\
          "<a href='http://test.host/review_mapping/delete_all_metareviewers?id=1'>No</a><br/>")
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end

    context 'when failed time is equal to 0' do
      it 'shows a note flash message and redirects to review_mapping#list_mappings page' do
        @metareview_response_maps.each do |metareview_response_map|
          allow(metareview_response_map).to receive(:delete).with(true)
        end
        request_params = { id: 1, force: true }
        post :delete_all_metareviewers, params: request_params
        expect(flash[:error]).to be nil
        expect(flash[:note]).to eq('All metareview mappings for contributor "reviewee" and reviewer "reviewer" have been deleted.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
  end

  describe '#unsubmit_review' do
    let(:review_response) { double('Response') }
    before(:each) do
      allow(Response).to receive(:where).with(map_id: '1').and_return([review_response])
      allow(ReviewResponseMap).to receive(:find_by).with(id: '1').and_return(review_response_map)
    end

    context 'when attributes of response are updated successfully' do
      it 'shows a success flash.now message and renders a .js.erb file' do
        allow(review_response).to receive(:update_attribute).with('is_submitted', false).and_return(true)
        params = { id: 1 }
        # xhr - XmlHttpRequest (AJAX)
        get :unsubmit_review, params: { id: 1 }, xhr: true
        expect(flash.now[:error]).to be nil
        expect(flash.now[:success]).to eq('The review by "reviewer" for "reviewee" has been unsubmitted.')
        expect(response).to render_template('unsubmit_review.js.erb')
      end
    end

    context 'when attributes of response are not updated successfully' do
      it 'shows an error flash.now message and renders a .js.erb file' do
        allow(review_response).to receive(:update_attribute).with('is_submitted', false).and_return(false)
        params = { id: 1 }
        # xhr - XmlHttpRequest (AJAX)
        get :unsubmit_review, params: { id: 1 }, xhr: true
        expect(flash.now[:success]).to be nil
        expect(flash.now[:error]).to eq('The review by "reviewer" for "reviewee" could not be unsubmitted.')
        expect(response).to render_template('unsubmit_review.js.erb')
      end
    end
  end

  describe '#delete_reviewer' do
    let(:review_response_map) { instance_double(ReviewResponseMap, id: 1) }
    let(:responses_relation)  { instance_double(ActiveRecord::Relation) }

    before do
      request.env['HTTP_REFERER'] = 'www.google.com'
      allow(ReviewResponseMap).to receive(:find_by).with(id: '1').and_return(review_response_map)
    end

    context 'when review_response_map is found' do
      context 'and responses exist' do
        it 'destroys the review map, shows success flash, and redirects' do
          allow(Response).to receive(:where).with(map_id: 1).and_return(responses_relation)
          allow(responses_relation).to receive(:exists?).and_return(true)
          allow(responses_relation).to receive(:pluck).with(:id).and_return([42])
          allow(responses_relation).to receive(:destroy_all)

          allow(Answer).to receive(:where).with(response_id: [42]).and_return(double(pluck: [99]))
          allow(AnswerTag).to receive(:where).with(answer_id: [99]).and_return(double(destroy_all: true))
          allow(Answer).to receive(:where).with(id: [99]).and_return(double(destroy_all: true))

          allow(review_response_map).to receive(:destroy)

          allow(review_response_map).to receive_message_chain(:reviewee, :name).and_return('reviewee')
          allow(review_response_map).to receive_message_chain(:reviewer, :name).and_return('reviewer')

          post :delete_reviewer, params: { id: 1 }
          expect(flash[:success]).to eq('The review mapping for "reviewee" and "reviewer" has been deleted.')
          expect(flash[:error]).to be_nil
          expect(response).to redirect_to('www.google.com')
        end
      end

      context 'and no responses exist' do
        it 'does NOT destroy the map, shows error flash, and redirects' do
          allow(Response).to receive(:where).with(map_id: 1).and_return(responses_relation)
          allow(responses_relation).to receive(:exists?).and_return(false)

          post :delete_reviewer, params: { id: 1 }
          expect(flash[:error]).to eq('This review has already been done. It cannot be deleted.')
          expect(flash[:success]).to be_nil
          expect(response).to redirect_to('www.google.com')
        end
      end
    end

    context 'when review_response_map is NOT found' do
      it 'shows an error flash and redirects' do
        allow(ReviewResponseMap).to receive(:find_by).with(id: '1').and_return(nil)

        post :delete_reviewer, params: { id: 1 }
        expect(flash[:error]).to eq('Review response map not found.')
        expect(flash[:success]).to be_nil
        expect(response).to redirect_to('www.google.com')
      end
    end
  end

  describe '#delete_metareviewer' do
    before(:each) do
      allow(MetareviewResponseMap).to receive(:find).with('1').and_return(metareview_response_map)
    end

    context 'when metareview_response_map can be deleted successfully' do
      it 'show a note flash message and redirects to review_mapping#list_mappings page' do
        allow(metareview_response_map).to receive(:delete).and_return(true)
        request_params = { id: 1 }
        post :delete_metareviewer, params: request_params
        expect(flash[:note]).to eq('The metareview mapping for reviewee and reviewer has been deleted.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end

    context 'when metareview_response_map cannot be deleted successfully' do
      it 'show a note flash message and redirects to review_mapping#list_mappings page' do
        allow(metareview_response_map).to receive(:delete).and_raise('Boom')
        request_params = { id: 1 }
        post :delete_metareviewer, params: request_params
        expect(flash[:error]).to eq("A delete action failed:<br/>Boom<a href='/review_mapping/delete_metareview/1'>Delete this mapping anyway>?")
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
  end

  describe '#delete_metareview' do
    it 'redirects to review_mapping#list_mappings page after deletion' do
      allow(MetareviewResponseMap).to receive(:find).with('1').and_return(metareview_response_map)
      allow(metareview_response_map).to receive(:delete).and_return(true)
      request_params = { id: 1 }
      post :delete_metareview, params: request_params
      expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
    end
  end

  describe '#list_mappings' do
    it 'renders review_mapping#list_mappings page' do
      allow(AssignmentTeam).to receive(:where).with(parent_id: 1).and_return([team, team1])
      request_params = {
        id: 1,
        msg: 'No error!'
      }
      get :list_mappings, params: request_params
      expect(flash[:error]).to eq('No error!')
      expect(response).to render_template(:list_mappings)
    end
  end

  describe '#automatic_review_mapping' do
    before(:each) do
      allow(AssignmentParticipant).to receive(:where).with(parent_id: 1).and_return([participant, participant1, participant2])
    end

    context 'when teams is not empty' do
      before(:each) do
        allow(AssignmentTeam).to receive(:where).with(parent_id: 1).and_return([team, team1])
      end

      context 'when all nums in params are 0' do
        it 'shows an error flash message and redirects to review_mapping#list_mappings page' do
          request_params = {
            id: 1,
            max_team_size: 1,
            num_reviews_per_student: 0,
            num_reviews_per_submission: 0,
            num_calibrated_artifacts: 0,
            num_uncalibrated_artifacts: 0
          }
          post :automatic_review_mapping, params: request_params
          expect(flash[:error]).to eq('Please choose either the number of reviews per student or the number of reviewers per team (student).')
          expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
        end
      end

      context 'when all nums in params are 0 except student_review_num' do
        it 'runs automatic review mapping strategy and redirects to review_mapping#list_mappings page' do
          allow_any_instance_of(ReviewMappingController).to receive(:automatic_review_mapping_strategy).with(any_args).and_return(true)
          request_params = {
            id: 1,
            max_team_size: 1,
            num_reviews_per_student: 1,
            num_reviews_per_submission: 0,
            num_calibrated_artifacts: 0,
            num_uncalibrated_artifacts: 0
          }
          post :automatic_review_mapping, params: request_params
          expect(flash[:error]).to be nil
          expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
        end
      end

      context 'when calibrated request_params are not 0' do
        it 'runs automatic review mapping strategy and redirects to review_mapping#list_mappings page' do
          allow(ReviewResponseMap).to receive(:where).with(reviewed_object_id: 1, calibrate_to: 1)
                                                     .and_return([double('ReviewResponseMap', reviewee_id: 2)])
          allow(AssignmentTeam).to receive(:find).with(2).and_return(team)
          allow_any_instance_of(ReviewMappingController).to receive(:automatic_review_mapping_strategy).with(any_args).and_return(true)
          request_params = {
            id: 1,
            max_team_size: 1,
            num_reviews_per_student: 1,
            num_reviews_per_submission: 0,
            num_calibrated_artifacts: 1,
            num_uncalibrated_artifacts: 1
          }
          post :automatic_review_mapping, params: request_params
          expect(flash[:error]).to be nil
          expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
        end
      end

      context 'when student review num is greater than or equal to team size' do
        it 'throws error stating that student review number cannot be greater than or equal to team size' do
          allow(ReviewResponseMap).to receive(:where)
            .with(reviewed_object_id: 1, calibrate_to: 1)
            .and_return([double('ReviewResponseMap', reviewee_id: 2)])
          allow(AssignmentTeam).to receive(:find).with(2).and_return(team)
          request_params = {
            id: 1,
            max_team_size: 1,
            num_reviews_per_student: 45,
            num_reviews_per_submission: 0,
            num_calibrated_artifacts: 0,
            num_uncalibrated_artifacts: 0
          }
          post :automatic_review_mapping, params: request_params
          expect(flash[:error]).to eq('You cannot set the number of reviews done ' \
                                      'by each student to be greater than or equal to total number of teams ' \
                                      '[or "participants" if it is an individual assignment].')
          expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
        end
      end
    end

    context 'when teams is empty, max team size is 1 and when review params are not 0' do
      it 'shows an error flash message and redirects to review_mapping#list_mappings page' do
        assignment_double = double('Assignment', auto_assign_mentor: false) 
        allow(Assignment).to receive(:find).and_return(assignment_double)
        allow(TeamsUser).to receive(:team_id).with(1, 2).and_return(true)
        allow(TeamsUser).to receive(:team_id).with(1, 3).and_return(false)
        allow(AssignmentTeam).to receive(:create_team_and_node).with(1).and_return(double('AssignmentTeam', id: 1))
        allow(ApplicationController).to receive_message_chain(:helpers, :create_team_users).with(no_args).with(user, 1).and_return(true)
        request_params = {
          id: 1,
          max_team_size: 1,
          num_reviews_per_student: 1,
          num_reviews_per_submission: 4,
          num_calibrated_artifacts: 0,
          num_uncalibrated_artifacts: 0
        }
        post :automatic_review_mapping, params: request_params
        expect(flash[:error]).to eq('Please choose either the number of reviews per student or the number of reviewers per team (student), not both.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
  end

  describe '#automatic_review_mapping_staggered' do
    let(:assignment) { build(:assignment, id: 1) }
    let(:request_params) do
      {
        id: assignment.id,
        assignment: {
          num_reviews: '4',
          num_metareviews: '2'
        }
      }
    end
    before(:each) do
      allow(Assignment).to receive(:find).with('1').and_return(assignment)
    end
    context 'when staggered review mapping is successful' do
      it 'assigns reviewers and shows success message' do
        success_message = 'Reviewers assigned successfully'
        allow(assignment).to receive(:assign_reviewers_staggered).with('4', '2').and_return(success_message)
        post :automatic_review_mapping_staggered, params: request_params
        expect(flash[:note]).to eq(success_message)
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
    context 'when staggered review mapping fails' do
      it 'handles the error gracefully' do
        error = StandardError.new('Failed to assign reviewers')
        allow(assignment).to receive(:assign_reviewers_staggered).with('4', '2').and_raise(error)

        post :automatic_review_mapping_staggered, params: request_params

        expect(flash[:error]).to eq(error.message)
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
    context 'with invalid parameters' do
      it 'handles missing parameters gracefully' do
        invalid_params = {
          id: assignment.id,
          assignment: {
            num_reviews: nil,
            num_metareviews: nil
          }
        }
        post :automatic_review_mapping_staggered, params: invalid_params
        expect(flash[:error]).to eq('Please specify the number of reviews and metareviews per student.')
        expect(response).to redirect_to('/review_mapping/list_mappings?id=1')
      end
    end
  end

  describe '#save_grade_and_comment_for_reviewer' do
    let(:review_grade) { build(:review_grade) }
    let(:instructor) { build(:instructor) }
    let(:request_params) do
      {
        review_grade: {
          participant_id: '1',
          grade_for_reviewer: '90',
          comment_for_reviewer: 'Great review!',
          assignment_id: '1'
        }
      }
    end
    before(:each) do
      session[:user] = instructor
    end
    context 'when saving grade and comment is successful' do
      it 'saves the review grade and shows success message' do
        allow(ReviewGrade).to receive(:find_or_create_by).with(participant_id: '1').and_return(review_grade)
        allow(review_grade).to receive(:attributes=).with(
          ActionController::Parameters.new({
            'grade_for_reviewer' => '90',
            'comment_for_reviewer' => 'Great review!'
          }).permit(
            :grade_for_reviewer,
            :comment_for_reviewer,
            :review_graded_at
          )
        )
        allow(review_grade).to receive(:review_graded_at=).with(any_args)
        allow(review_grade).to receive(:reviewer_id=).with(instructor.id)
        allow(review_grade).to receive(:save!).and_return(true)   
        post :save_grade_and_comment_for_reviewer, params: request_params    
        expect(flash[:success]).to eq('Grade and comment for reviewer successfully saved.')
        expect(response).to redirect_to('/reports/response_report?id=1')
      end
    end   
    context 'when saving grade and comment fails' do
      it 'shows error message and redirects' do
        error = StandardError.new('Save failed')
        allow(ReviewGrade).to receive(:find_or_create_by).with(participant_id: '1').and_return(review_grade)
        allow(review_grade).to receive(:attributes=).with(
          ActionController::Parameters.new({
            'grade_for_reviewer' => '90',
            'comment_for_reviewer' => 'Great review!'
          }).permit(
            :grade_for_reviewer,
            :comment_for_reviewer,
            :review_graded_at
          )
        )
        allow(review_grade).to receive(:review_graded_at=).with(any_args)
        allow(review_grade).to receive(:reviewer_id=).with(instructor.id)
        allow(review_grade).to receive(:save!).and_raise(error)
        post :save_grade_and_comment_for_reviewer, params: request_params
        expect(flash[:error]).to eq(error.message)
        expect(response).to redirect_to('/reports/response_report?id=1')
      end
    end
    context 'when responding to JS format' do
      it 'renders the JS template' do
        allow(ReviewGrade).to receive(:find_or_create_by).with(participant_id: '1').and_return(review_grade)
        allow(review_grade).to receive(:attributes=).with(
          ActionController::Parameters.new({
            'grade_for_reviewer' => '90',
            'comment_for_reviewer' => 'Great review!'
          }).permit(
            :grade_for_reviewer,
            :comment_for_reviewer,
            :review_graded_at
          )
        )
        allow(review_grade).to receive(:review_graded_at=).with(any_args)
        allow(review_grade).to receive(:reviewer_id=).with(instructor.id)
        allow(review_grade).to receive(:save!).and_return(true)
        post :save_grade_and_comment_for_reviewer, params: request_params, format: :js
        expect(response).to render_template('review_mapping/save_grade_and_comment_for_reviewer')
      end
    end
  end

  describe '#start_self_review' do
    let(:assignment) { build(:assignment, id: 1) }
    let(:team) { build(:assignment_team, id: 1) }
    let(:user_id) { '1' }
    let(:reviewer_id) { '1' }
    let(:request_params) do
      {
        assignment_id: assignment.id,
        reviewer_id: reviewer_id,
        reviewer_userid: user_id
      }
    end

    before(:each) do
      allow(Assignment).to receive(:find).with('1').and_return(assignment)
    end

    context 'when self review is created successfully' do
      it 'redirects to edit page' do
        allow(Team).to receive(:find_team_for_assignment_and_user).with(assignment.id, user_id).and_return([team])
        allow(SelfReviewResponseMap).to receive(:create_self_review).with(team.id, reviewer_id, assignment.id).and_return(true)

        post :start_self_review, params: request_params

        expect(response).to redirect_to(controller: 'submitted_content', action: 'edit', id: reviewer_id)
      end
    end

    context 'when self review creation fails' do
      it 'redirects with error message' do
        error = StandardError.new('Self review already exists')
        allow(Team).to receive(:find_team_for_assignment_and_user).with(assignment.id, user_id).and_return([team])
        allow(SelfReviewResponseMap).to receive(:create_self_review).with(team.id, reviewer_id, assignment.id).and_raise(error)
        post :start_self_review, params: request_params
        expect(response).to redirect_to(controller: 'submitted_content', action: 'edit', id: reviewer_id, msg: error.message)
      end
    end
    context 'when team is not found' do
      it 'redirects with error message' do
        allow(Team).to receive(:find_team_for_assignment_and_user).with(assignment.id, user_id).and_return([])
        post :start_self_review, params: request_params
        expect(response).to redirect_to(controller: 'submitted_content', action: 'edit', id: reviewer_id, msg: 'No team is found for this user')
      end
    end
  end

  describe '#automatic_review_mapping_strategy' do
    let(:assignment_id) { 1 }
    let(:participants) { [participant, participant1, participant2] }
    let(:teams) { [team, team1] }
    let(:student_review_num) { 2 }
    let(:submission_review_num) { 2 }
    let(:exclude_teams) { false }
    before(:each) do
      allow(ReviewMappingHelper).to receive(:initialize_reviewer_counts).with(participants).and_return({})
      allow(ReviewMappingHelper).to receive(:filter_eligible_teams).with(teams, exclude_teams).and_return(teams)
      allow(ReviewMappingHelper).to receive(:create_review_strategy).with(participants, teams, student_review_num, submission_review_num).and_return(double('ReviewStrategy'))
    end
    context 'when initial review assignment is successful' do
      it 'assigns initial reviews and remaining reviews' do
        review_strategy = double('ReviewStrategy')
        allow(ReviewMappingHelper).to receive(:create_review_strategy).and_return(review_strategy)        
        expect_any_instance_of(ReviewMappingController).to receive(:assign_initial_reviews).with(assignment_id, review_strategy, {})
        expect_any_instance_of(ReviewMappingController).to receive(:assign_remaining_reviews).with(assignment_id, review_strategy, {})        
        controller.send(:automatic_review_mapping_strategy, assignment_id, participants, teams, student_review_num, submission_review_num, exclude_teams)
      end
    end
    context 'when exclude_teams is true' do
      it 'filters out teams correctly' do
        allow(ReviewMappingHelper).to receive(:filter_eligible_teams).with(teams, true).and_return([team])        
        review_strategy = double('ReviewStrategy')
        allow(ReviewMappingHelper).to receive(:create_review_strategy).with(participants, [team], student_review_num, submission_review_num).and_return(review_strategy)        
        expect_any_instance_of(ReviewMappingController).to receive(:assign_initial_reviews).with(assignment_id, review_strategy, {})
        expect_any_instance_of(ReviewMappingController).to receive(:assign_remaining_reviews).with(assignment_id, review_strategy, {})        
        controller.send(:automatic_review_mapping_strategy, assignment_id, participants, teams, student_review_num, submission_review_num, true)
      end
    end
  end
end

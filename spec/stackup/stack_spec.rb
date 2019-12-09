require "spec_helper"

require "stackup/stack"

describe Stackup::Stack do

  let(:cf_client) { stub_cf_client }

  let(:stack_name) { "stack_name" }
  let(:unique_stack_id) { "ID:#{stack_name}" }
  let(:stack_options) { {} }

  let(:change_set_name) { "ch-ch-changes" }

  subject(:stack) { described_class.new(stack_name, cf_client, stack_options) }

  before do
    cf_client.stub_responses(:describe_stacks, *describe_stacks_responses)
    cf_client.stub_responses(:describe_change_set, *describe_change_set_responses)
    allow(stack).to receive(:sleep).at_most(5).times
    # partial stubbing, to support spying
    allow(cf_client).to receive(:create_stack).and_call_original
    allow(cf_client).to receive(:delete_stack).and_call_original
    allow(cf_client).to receive(:update_stack).and_call_original
    allow(cf_client).to receive(:cancel_update_stack).and_call_original
    allow(cf_client).to receive(:list_change_sets).and_call_original
    allow(cf_client).to receive(:create_change_set).and_call_original
    allow(cf_client).to receive(:execute_change_set).and_call_original
    allow(cf_client).to receive(:delete_change_set).and_call_original
    allow(cf_client).to receive(:describe_change_set).and_call_original
  end

  def error(type, message)
    {
      :status_code => 400,
      :headers => {},
      :body => [
        "<ErrorResponse><Error><Code>#{type}</Code><Message>",
        message,
        "</Message></Error></ErrorResponse>"
      ].join
    }
  end

  def validation_error(message)
    error("ValidationError", message)
  end

  def stack_description(stack_status, details = {})
    {
      :stacks => [
        {
          :creation_time => Time.now - 100,
          :stack_id => unique_stack_id,
          :stack_name => stack_name,
          :stack_status => stack_status
        }.merge(details)
      ]
    }
  end

  let(:describe_change_set_responses) do
    [
      {
        :status => "CREATE_COMPLETE"
      }
    ]
  end

  context "before stack exists" do

    let(:describe_stacks_responses) do
      [
        validation_error("Stack with id #{stack_name} does not exist")
      ]
    end

    describe "#exists?" do
      it "is false" do
        expect(stack.exists?).to be false
      end
    end

    describe "#status" do
      it "raises a NoSuchStack error" do
        expect { stack.status }.to raise_error(Stackup::NoSuchStack)
      end
    end

    describe "#delete" do
      it "returns nil" do
        expect(stack.delete).to be_nil
      end
    end

    describe "#create_or_update" do

      let(:template) { "stack template" }

      let(:options) do
        { :template_body => template }
      end

      def create_or_update
        stack.create_or_update(options)
      end

      let(:describe_stacks_responses) do
        super() + [
          stack_description("CREATE_IN_PROGRESS"),
          stack_description(final_status)
        ]
      end

      let(:final_status) { "CREATE_COMPLETE" }

      it "calls :create_stack" do
        expected_args = {
          :stack_name => stack_name,
          :template_body => template
        }
        create_or_update
        expect(cf_client).to have_received(:create_stack)
          .with(hash_including(expected_args))
      end

      it "it sleeps" do
        create_or_update
        expect(stack).to have_received(:sleep).with(5)
      end

      it "returns status" do
        expect(create_or_update).to eq("CREATE_COMPLETE")
      end

      context "with :wait = false" do

        let(:stack_options) { { :wait => false } }

        it "calls :create_stack" do
          expected_args = {
            :stack_name => stack_name,
            :template_body => template
          }
          create_or_update
          expect(cf_client).to have_received(:create_stack)
            .with(hash_including(expected_args))
        end

        it "it does not sleep" do
          create_or_update
          expect(stack).not_to have_received(:sleep)
        end

        it "returns initial status" do
          expect(create_or_update).to eq("CREATE_IN_PROGRESS")
        end

      end

      context "unsuccessful" do

        let(:final_status) { "CREATE_FAILED" }

        it "raises a StackUpdateError" do
          expect { create_or_update }
            .to raise_error(Stackup::StackUpdateError)
        end

      end

      context "with a custom wait_poll_interval" do

        let(:stack_options) do
          { :wait_poll_interval => 12.3 }
        end

        it "it sleeps for the specified interval" do
          create_or_update
          expect(stack).to have_received(:sleep).with(12.3)
        end

      end

      context "with :template as data" do

        let(:options) do
          { :template => { "foo" => "bar" } }
        end

        it "converts the template to JSON" do
          create_or_update
          expect(cf_client).to have_received(:create_stack)
            .with(hash_including(:template_body))
        end

      end

      context "with :parameters as Hash" do

        before do
          options[:parameters] = { "foo" => "bar" }
        end

        it "converts them to an Array" do
          expected_parameters = [
            {
              :parameter_key => "foo",
              :parameter_value => "bar"
            }
          ]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:parameters]).to eq(expected_parameters)
          end
        end

      end

      context "with :parameters in awscli form" do

        before do
          options[:parameters] = [{
            "ParameterKey" => "foo",
            "ParameterValue" => "bar"
          }]
        end

        it "converts the keys to aws-sdk form" do
          expected_parameters = [
            {
              :parameter_key => "foo",
              :parameter_value => "bar"
            }
          ]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:parameters]).to eq(expected_parameters)
          end
        end

      end

      context "with :tags as Hash" do

        before do
          options[:tags] = { "foo" => "bar", "code" => 123 }
        end

        it "converts them to an Array" do
          expected_tags = [
            { :key => "foo", :value => "bar" },
            { :key => "code", :value => "123" }
          ]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:tags]).to eq(expected_tags)
          end
        end

      end

      context "with :tags in SDK form as they arrive from file" do

        before do
          options[:tags] = [
            { "Key" => "foo", "Value" => "bar" }
          ]
        end

        it "converts them to an Array, that uses symbols as keys" do
          expected_tags = [
            { :key => "foo", :value => "bar" },
          ]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:tags]).to eq(expected_tags)
          end
        end

      end

      context "with :tags in SDK form" do

        before do
          options[:tags] = [
            { :key => "foo", :value => "bar" }
          ]
        end

        it "passes them through" do
          expected_tags = [
            { :key => "foo", :value => "bar" }
          ]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:tags]).to eq(expected_tags)
          end
        end

      end

      context "with :capabilities as an Array" do

        before do
          options[:capabilities] = %w[CAPABILITY_IAM CAPABILITY_NAMED_IAM]
        end

        it "passes them through" do
          expected_capabilities = %w[CAPABILITY_IAM CAPABILITY_NAMED_IAM]
          create_or_update
          expect(cf_client).to have_received(:create_stack) do |options|
            expect(options[:capabilities]).to eq(expected_capabilities)
          end
        end

      end

    end

    describe "#change_set#create" do

      let(:template) { "stack template" }

      let(:options) do
        { :template_body => template }
      end

      def create_change_set
        stack.change_set(change_set_name).create(options)
      end

      it "calls :create_change_set" do
        expected_args = {
          :stack_name => stack_name,
          :change_set_name => change_set_name,
          :change_set_type => "CREATE",
          :template_body => template
        }
        create_change_set
        expect(cf_client).to have_received(:create_change_set)
          .with(hash_including(expected_args))
      end

      context "with :template as data" do

        let(:options) do
          { :template => { "foo" => "bar" } }
        end

        it "converts the template to JSON" do
          create_change_set
          expect(cf_client).to have_received(:create_change_set)
            .with(hash_including(:template_body))
        end

      end

      context "with :parameters as Hash" do

        before do
          options[:parameters] = { "foo" => "bar" }
        end

        it "converts them to an Array" do
          expected_parameters = [
            {
              :parameter_key => "foo",
              :parameter_value => "bar"
            }
          ]
          create_change_set
          expect(cf_client).to have_received(:create_change_set) do |options|
            expect(options[:parameters]).to eq(expected_parameters)
          end
        end

      end

      context "with :tags as Hash" do

        before do
          options[:tags] = { "foo" => "bar", "code" => 123 }
        end

        it "converts them to an Array" do
          expected_tags = [
            { :key => "foo", :value => "bar" },
            { :key => "code", :value => "123" }
          ]
          create_change_set
          expect(cf_client).to have_received(:create_change_set) do |options|
            expect(options[:tags]).to eq(expected_tags)
          end
        end

      end

      context "with :capabilities as an Array" do

        before do
          options[:capabilities] = %w[CAPABILITY_IAM CAPABILITY_NAMED_IAM]
        end

        it "passes them through" do
          expected_capabilities = %w[CAPABILITY_IAM CAPABILITY_NAMED_IAM]
          create_change_set
          expect(cf_client).to have_received(:create_change_set) do |options|
            expect(options[:capabilities]).to eq(expected_capabilities)
          end
        end

      end

    end

    describe "#change_set#execute" do

      let(:change_set_name) { "create-it" }

      let(:describe_stacks_responses) do
        [
          stack_description("CREATE_IN_PROGRESS"),
          stack_description("CREATE_COMPLETE")
        ]
      end

      def execute_change_set
        stack.change_set(change_set_name).execute
      end

      it "calls :execute_change_set" do
        execute_change_set
        expected_args = {
          :stack_name => stack_name,
          :change_set_name => change_set_name
        }
        expect(cf_client).to have_received(:execute_change_set)
          .with(hash_including(expected_args))
      end

      it "returns status" do
        expect(execute_change_set).to eq("CREATE_COMPLETE")
      end

    end

  end

  context "with existing stack" do

    let(:stack_status) { "CREATE_COMPLETE" }

    let(:describe_stacks_responses) do
      [
        stack_description(stack_status)
      ]
    end

    describe "#exists?" do
      it "is true" do
        expect(stack.exists?).to be true
      end
    end

    describe "#status" do
      it "returns the stack status" do
        expect(stack.status).to eq(stack_status)
      end
    end

    describe "#tags" do

      let(:tags) do
        [
          { :key => "foo", :value => "bar" }
        ]
      end

      let(:describe_stacks_responses) do
        [
          stack_description(stack_status, :tags => tags)
        ]
      end

      it "returns tags as a Hash" do
        expect(stack.tags).to eq("foo" => "bar")
      end

    end

    describe "#delete" do

      context "if successful" do

        let(:describe_stacks_responses) do
          super() + [
            stack_description("DELETE_IN_PROGRESS"),
            stack_description("DELETE_COMPLETE")
          ]
        end

        it "calls delete_stack" do
          stack.delete
          expect(cf_client).to have_received(:delete_stack)
            .with(hash_including(:stack_name => unique_stack_id))
        end

        it "returns status" do
          expect(stack.delete).to eq("DELETE_COMPLETE")
        end

      end

      context "if unsuccessful" do

        let(:describe_stacks_responses) do
          super() + [
            stack_description("DELETE_IN_PROGRESS"),
            stack_description("DELETE_FAILED")
          ]
        end

        it "raises a StackUpdateError" do
          expect { stack.delete }.to raise_error(Stackup::StackUpdateError)
        end

      end

    end

    describe "#create_or_update" do

      let(:template) { "stack template" }

      let(:options) do
        { :template_body => template }
      end

      def create_or_update
        stack.create_or_update(options)
      end

      let(:describe_stacks_responses) do
        super() + [
          stack_description("UPDATE_IN_PROGRESS"),
          stack_description(final_status)
        ]
      end

      let(:final_status) { "UPDATE_COMPLETE" }

      it "calls :update_stack" do
        expected_args = {
          :stack_name => stack_name,
          :template_body => template
        }
        create_or_update
        expect(cf_client).to have_received(:update_stack)
          .with(hash_including(expected_args))
      end

      context "successful" do

        it "returns status" do
          expect(create_or_update).to eq(final_status)
        end

        context "if no updates are required" do

          before do
            cf_client.stub_responses(
              :update_stack,
              validation_error("No updates are to be performed.")
            )
          end

          it "returns nil" do
            expect(create_or_update).to be_nil
          end

        end

      end

      context "unsuccessful" do

        let(:final_status) { "UPDATE_ROLLBACK_COMPLETE" }

        it "raises a StackUpdateError" do
          expect { create_or_update }.to raise_error(Stackup::StackUpdateError)
        end

      end

      context "with :disable_rollback" do

        before do
          options[:disable_rollback] = true
        end

        it "calls :update_stack" do
          create_or_update
          expect(cf_client).to have_received(:update_stack)
            .with(hash_not_including(:disable_rollback))
        end

      end

    end

    describe "#change_set_summaries" do

      it "calls :list_change_sets" do
        cf_client.stub_responses(:list_change_sets, :summaries => [
                                   { :change_set_name => "take1" },
                                   { :change_set_name => "take2" }
                                 ])
        summaries = stack.change_set_summaries
        expect(summaries.map(&:change_set_name)).to eql(%w[take1 take2])
        expect(cf_client).to have_received(:list_change_sets)
          .with(:stack_name => stack_name)
      end

    end

    describe "#change_set#create" do

      let(:template) { "stack template" }

      let(:options) do
        { :template_body => template }
      end

      def create_change_set
        stack.change_set(change_set_name).create(options)
      end

      it "calls :create_change_set" do
        expected_args = {
          :stack_name => stack_name,
          :change_set_name => change_set_name,
          :change_set_type => "UPDATE",
          :template_body => template
        }
        create_change_set
        expect(cf_client).to have_received(:create_change_set)
          .with(hash_including(expected_args))
      end

    end

    describe "#change_set#execute" do

      let(:change_set_name) { "change-it" }

      let(:describe_stacks_responses) do
        [
          stack_description("UPDATE_IN_PROGRESS"),
          stack_description("UPDATE_COMPLETE")
        ]
      end

      def execute_change_set
        stack.change_set(change_set_name).execute
      end

      it "calls :execute_change_set" do
        execute_change_set
        expected_args = {
          :stack_name => stack_name,
          :change_set_name => change_set_name
        }
        expect(cf_client).to have_received(:execute_change_set)
          .with(hash_including(expected_args))
      end

      it "it sleeps" do
        execute_change_set
        expect(stack).to have_received(:sleep).with(5)
      end

      it "returns status" do
        expect(execute_change_set).to eq("UPDATE_COMPLETE")
      end

      context "if change-set doesn't exist" do

        before do
          cf_client.stub_responses(
            :execute_change_set,
            error("ChangeSetNotFound", "ChangeSet [foo] does not exist")
          )
        end

        it "raises a NoSuchChangeSet error" do
          expect { execute_change_set }.to raise_error(Stackup::NoSuchChangeSet)
        end

      end

    end

    describe "#change_set#delete" do

      let(:change_set_name) { "change-it" }

      it "calls :delete_change_set" do
        stack.change_set(change_set_name).delete
        expected_args = {
          :stack_name => stack_name,
          :change_set_name => change_set_name
        }
        expect(cf_client).to have_received(:delete_change_set)
          .with(hash_including(expected_args))
      end

    end

    %w[CREATE_FAILED ROLLBACK_COMPLETE].each do |initial_status|
      context "when status is #{initial_status}" do

        let(:stack_status) { initial_status }

        describe "#create_or_update" do

          let(:template) { "stack template" }

          def create_or_update
            stack.create_or_update(:template_body => template, :disable_rollback => true)
          end

          let(:describe_stacks_responses) do
            super() + [
              stack_description("DELETE_IN_PROGRESS"),
              validation_error("Stack with id #{stack_name} does not exist"),
              stack_description("CREATE_IN_PROGRESS"),
              stack_description("CREATE_COMPLETE")
            ]
          end

          before do
            cf_client.stub_responses(
              :update_stack,
              validation_error("Stack [woollyams-test] does not exist")
            )
          end

          it "calls :delete_stack, then :create_stack" do
            create_or_update
            expect(cf_client).to have_received(:delete_stack)
            expect(cf_client).to have_received(:create_stack)

            expected_args = {
              :stack_name => stack_name,
              :template_body => template,
              :disable_rollback => true
            }
            expect(cf_client).to have_received(:create_stack)
              .with(hash_including(expected_args))
          end

        end

      end
    end

    context "when status is stable" do

      before do
        cf_client.stub_responses(
          :cancel_update_stack,
          validation_error("that cannot be called from current stack status")
        )
      end

      describe "#cancel_update" do

        it "returns nil" do
          expect(stack.cancel_update).to be_nil
        end

      end

    end

    context "when status is UPDATE_IN_PROGRESS" do

      let(:stack_status) { "UPDATE_IN_PROGRESS" }

      describe "#cancel_update" do

        let(:describe_stacks_responses) do
          super() + [
            stack_description("UPDATE_ROLLBACK_IN_PROGRESS"),
            stack_description("UPDATE_ROLLBACK_COMPLETE")
          ]
        end

        it "calls :cancel_update_stack" do
          expected_args = {
            :stack_name => stack_name
          }
          stack.cancel_update
          expect(cf_client).to have_received(:cancel_update_stack)
            .with(hash_including(expected_args))
        end

        it "returns status" do
          expect(stack.cancel_update).to eq("UPDATE_ROLLBACK_COMPLETE")
        end

      end

    end

  end

end

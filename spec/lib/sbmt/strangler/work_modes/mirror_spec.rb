# frozen_string_literal: true

require_relative "shared_context"

describe Sbmt::Strangler::WorkModes::Mirror do
  describe "#call" do
    include_context "with work mode implementation context"

    let(:http_params) { {a: 345, f: "abc"} }
    let(:origin_response) { Dry::Monads::Success.new(body: '["origin_response"]', status: 200) }

    before do
      # Proxying
      allow(rails_controller).to receive(:http_params).and_return(http_params)
      allow(rails_controller).to receive(:http_request).with(http_params).and_return(origin_response)
      allow(rails_controller).to receive(:render_origin_response)

      # Metrics
      allow(metric_tracker).to receive(:track_mirror_call)
      allow(metric_tracker).to receive(:track_compare_call)
      allow(metric_tracker).to receive(:track_compare_call_result)

      # Lambdas
      allow(strangler_action.mirror).to receive(:call).and_call_original
      allow(strangler_action.compare).to receive(:call).and_call_original
    end

    it "renders origin response" do
      mode.call
      expect(rails_controller).to have_received(:render_origin_response).with(origin_response)
    end

    it "calls action.mirror lambda" do
      mode.call
      expect(strangler_action.mirror).to have_received(:call).with(rails_controller)
    end

    it "tracks action.mirror block call" do
      mode.call
      expect(metric_tracker).to have_received(:track_mirror_call).with(true)
    end

    it "calls action.compare lambda" do
      mode.call
      expect(strangler_action.compare).to have_received(:call).with(origin_response.success, mirror_result)
    end

    context "when origin response contains body, status and headers" do
      let(:origin_response) do
        Dry::Monads::Success.new(
          body: '["origin_response"]',
          headers: ActionDispatch::Http::Headers.new("Some-Header" => "HVAL"),
          status: 200
        )
      end

      it "calls action.compare lambda with a duplicate of origin response data" do
        expect(strangler_action.compare).to receive(:call) do |received_origin_result, _received_mirror_result|
          expect(received_origin_result.object_id).not_to eq(origin_response.success.object_id)
          expect(received_origin_result[:body].object_id).not_to eq(origin_response.success[:body].object_id)
          expect(received_origin_result[:headers].object_id).not_to eq(origin_response.success[:headers].object_id)
          expect(received_origin_result[:status]).to eq(200)
        end
        mode.call
      end
    end

    it "tracks action.compare block call" do
      mode.call
      expect(metric_tracker).to have_received(:track_compare_call).with(true)
    end

    it "tracks action.compare block result" do
      mode.call
      expect(metric_tracker).to have_received(:track_compare_call_result).with(compare_result)
    end

    context "when action.mirror block call raised error" do
      let(:error) { RuntimeError.new("something went wrong") }

      before do
        allow(strangler_action.mirror).to receive(:call).and_raise(error)
      end

      it "renders origin response" do
        mode.call
        expect(rails_controller).to have_received(:render_origin_response).with(origin_response)
      end

      it "tracks action.mirror block failure" do
        mode.call
        expect(metric_tracker).to have_received(:track_mirror_call).with(false)
      end

      it "doesn't call action.compare lambda" do
        mode.call
        expect(strangler_action.compare).not_to have_received(:call)
      end

      it "tracks/logs error" do
        expect(Sbmt::Strangler.error_tracker).to receive(:error).with(error)
        expect(Sbmt::Strangler.logger).to receive(:error).with(error)
        mode.call
      end
    end

    context "when action.compare block call raised error" do
      let(:error) { RuntimeError.new("something went wrong") }

      before do
        allow(strangler_action.compare).to receive(:call).and_raise(error)
      end

      it "renders origin response" do
        mode.call
        expect(rails_controller).to have_received(:render_origin_response).with(origin_response)
      end

      it "tracks action.compare block failure" do
        mode.call
        expect(metric_tracker).to have_received(:track_compare_call).with(false)
      end

      it "doesn't track action.compare block result" do
        mode.call
        expect(metric_tracker).not_to have_received(:track_compare_call_result)
      end

      it "tracks/logs error" do
        expect(Sbmt::Strangler.error_tracker).to receive(:error).with(error)
        expect(Sbmt::Strangler.logger).to receive(:error).with(error)
        mode.call
      end
    end

    context "when action.compare block call retruned non-boolean value" do
      before do
        allow(strangler_action.compare).to receive(:call).and_return("not a bool")
      end

      it "renders origin response" do
        mode.call
        expect(rails_controller).to have_received(:render_origin_response).with(origin_response)
      end

      it "tracks action.compare block failure" do
        mode.call
        expect(metric_tracker).to have_received(:track_compare_call).with(false)
      end

      it "doesn't track action.compare block result" do
        mode.call
        expect(metric_tracker).not_to have_received(:track_compare_call_result)
      end

      it "tracks/logs error" do
        err = an_instance_of(RuntimeError).and have_attributes(message: /must return a boolean value/)
        expect(Sbmt::Strangler.error_tracker).to receive(:error).with(err)
        expect(Sbmt::Strangler.logger).to receive(:error).with(err)
        mode.call
      end
    end

    context "when origin response was not successfull" do
      let(:origin_response) { Dry::Monads::Failure.new(body: '["origin_error"]', status: 500) }

      it "renders origin response" do
        mode.call
        expect(rails_controller).to have_received(:render_origin_response).with(origin_response)
      end

      it "calls action.compare lambda" do
        mode.call
        expect(strangler_action.compare).to have_received(:call).with(origin_response.failure, mirror_result)
      end
    end
  end
end

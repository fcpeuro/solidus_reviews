# frozen_string_literal: true

module Spree
  module Api
    class ReviewsController < Spree::Api::BaseController
      before_action :load_review, only: [:show, :update, :destroy]
      before_action :load_product, :find_review_user
      before_action :sanitize_rating, only: [:create, :update]
      before_action :prevent_multiple_reviews, only: [:create]

      def index
        @reviews = if @product
                     Spree::Review.default_approval_filter.where(product: @product)
                   else
                     Spree::Review.where(user: @review_user)
                   end

        render json: {
          reviews: @reviews.as_json(include: [:images, :feedback_reviews]),
          avg_rating: @product&.avg_rating
        }
      end

      def show
        authorize! :read, @review
        render json: @review, include: [:images, :feedback_reviews]
      end

      def create
        return not_found if @product.nil?

        @review = Spree::Review.new(review_params)
        @review.product = @product
        @review.user = @review_user
        @review.ip_address = request.remote_ip
        @review.locale = I18n.locale.to_s if Spree::Reviews::Config[:track_locale]

        authorize! :create, @review
        if @review.save
          render json: @review, include: [:images, :feedback_reviews], status: :created
        else
          invalid_resource!(@review)
        end
      end

      def update
        authorize! :update, @review

        attributes = review_params.merge(ip_address: request.remote_ip, approved: false)

        if @review.update(attributes)
          render json: @review, include: [:images, :feedback_reviews], status: :ok
        else
          invalid_resource!(@review)
        end
      end

      def destroy
        authorize! :destroy, @review

        if @review.destroy
          render json: @review, status: :ok
        else
          invalid_resource!(@review)
        end
      end

      private

      def permitted_review_attributes
        [:product_id, :rating, :title, :review, :name, :show_identifier]
      end

      def review_params
        params.permit(permitted_review_attributes)
      end

      # Loads product from product id.
      def load_product
        @product = if params[:product_id]
                     Spree::Product.friendly.find(params[:product_id])
                   else
                     @review&.product
                   end
      end

      # Finds user based on api_key or by user_id if api_key belongs to an admin.
      def find_review_user
        @review_user = if params[:user_id] && current_user_roles.include?('admin')
                         Spree.user_class.find(params[:user_id])
                       else
                         current_api_user
                       end
      end

      # Loads any review that is shared between the user and product
      def load_review
        @review = Spree::Review.find(params[:id])
      end

      # Ensures that a user can't create more than 1 review per product
      def prevent_multiple_reviews
        @review = @review_user.reviews.find_by(product: @product)
        if @review.present?
          invalid_resource!(@review)
        end
      end

      # Converts rating strings like "5 units" to "5"
      # Operates on params
      def sanitize_rating
        params[:rating].sub!(/\s*[^0-9]*\z/, '') if params[:rating].present?
      end
    end
  end
end

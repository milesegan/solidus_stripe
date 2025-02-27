# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Stripe checkout", type: :feature do
  let(:zone) { FactoryBot.create(:zone) }
  let(:country) { FactoryBot.create(:country) }

  before do
    FactoryBot.create(:store)
    zone.members << Spree::ZoneMember.create!(zoneable: country)
    FactoryBot.create(:free_shipping_method)

    Spree::PaymentMethod::StripeCreditCard.create!(
      name: "Stripe",
      preferred_secret_key: "sk_test_VCZnDv3GLU15TRvn8i2EsaAN",
      preferred_publishable_key: "pk_test_Cuf0PNtiAkkMpTVC2gwYDMIg",
      preferred_v3_elements: preferred_v3_elements,
      preferred_v3_intents: preferred_v3_intents
    )

    FactoryBot.create(:product, name: "DL-44")

    visit spree.root_path
    click_link "DL-44"
    click_button "Add To Cart"

    expect(page).to have_current_path("/cart")
    click_button "Checkout"

    expect(page).to have_current_path("/checkout/registration")
    click_link "Create a new account"
    within("#new_spree_user") do
      fill_in "Email", with: "mary@example.com"
      fill_in "Password", with: "superStrongPassword"
      fill_in "Password Confirmation", with: "superStrongPassword"
    end
    click_button "Create"

    # Address
    expect(page).to have_current_path("/checkout/address")

    within("#billing") do
      fill_in_name
      fill_in "Street Address", with: "YT-1300"
      fill_in "City", with: "Mos Eisley"
      select "United States of America", from: "Country"
      select country.states.first.name, from: "order_bill_address_attributes_state_id"
      fill_in "Zip", with: "12010"
      fill_in "Phone", with: "(555) 555-5555"
    end
    click_on "Save and Continue"

    # Delivery
    expect(page).to have_current_path("/checkout/delivery")
    expect(page).to have_content("UPS Ground")
  end

  # This will fetch a token from Stripe.com and then pass that to the webserver.
  # The server then processes the payment using that token.

  context 'when using Stripe V2 API library' do
    let(:preferred_v3_elements) { false }
    let(:preferred_v3_intents) { false }

    before do
      click_on "Save and Continue"
      expect(page).to have_current_path("/checkout/payment")
    end

    it "can process a valid payment", js: true do
      fill_in "Card Number", with: "4242 4242 4242 4242"
      fill_in "Card Code", with: "123"
      fill_in "Expiration", with: "01 / #{Time.now.year + 1}"
      click_button "Save and Continue"
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")
    end

    it "can re-use saved cards", js: true do
      fill_in "Card Number", with: "4242 4242 4242 4242"
      fill_in "Card Code", with: "123"
      fill_in "Expiration", with: "01 / #{Time.now.year + 1}"
      click_button "Save and Continue"

      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")

      visit spree.root_path
      click_link "DL-44"
      click_button "Add To Cart"

      expect(page).to have_current_path("/cart")
      click_button "Checkout"

      # Address
      expect(page).to have_current_path("/checkout/address")

      within("#billing") do
        fill_in_name
        fill_in "Street Address", with: "YT-1300"
        fill_in "City", with: "Mos Eisley"
        select "United States of America", from: "Country"
        select country.states.first.name, from: "order_bill_address_attributes_state_id"
        fill_in "Zip", with: "12010"
        fill_in "Phone", with: "(555) 555-5555"
      end
      click_on "Save and Continue"

      # Delivery
      expect(page).to have_current_path("/checkout/delivery")
      expect(page).to have_content("UPS Ground")
      click_on "Save and Continue"

      # Payment
      expect(page).to have_current_path("/checkout/payment")
      choose "Use an existing card on file"
      click_button "Save and Continue"

      # Confirm
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")
    end

    it "shows an error with a missing credit card number", js: true do
      fill_in "Expiration", with: "01 / #{Time.now.year + 1}"
      click_button "Save and Continue"
      expect(page).to have_content("Could not find payment information")
    end

    it "shows an error with a missing expiration date", js: true do
      fill_in "Card Number", with: "4242 4242 4242 4242"
      click_button "Save and Continue"
      expect(page).to have_content("Your card's expiration year is invalid.")
    end

    it "shows an error with an invalid credit card number", js: true do
      fill_in "Card Number", with: "1111 1111 1111 1111"
      fill_in "Expiration", with: "01 / #{Time.now.year + 1}"
      click_button "Save and Continue"
      expect(page).to have_content("Your card number is incorrect.")
    end

    it "shows an error with invalid security fields", js: true do
      fill_in "Card Number", with: "4242 4242 4242 4242"
      fill_in "Expiration", with: "01 / #{Time.now.year + 1}"
      fill_in "Card Code", with: "12"
      click_button "Save and Continue"
      expect(page).to have_content("Your card's security code is invalid.")
    end

    it "shows an error with invalid expiry fields", js: true do
      fill_in "Card Number", with: "4242 4242 4242 4242"
      fill_in "Expiration", with: "00 / #{Time.now.year + 1}"
      fill_in "Card Code", with: "123"
      click_button "Save and Continue"
      expect(page).to have_content("Your card's expiration month is invalid.")
    end
  end

  shared_examples "Stripe Elements invalid payments" do
    it "shows an error with a missing credit card number" do
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"
      expect(page).to have_content("Your card number is incomplete.")
    end

    it "shows an error with a missing expiration date" do
      within_frame find('#card_number iframe') do
        '4242 4242 4242 4242'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      click_button "Save and Continue"
      expect(page).to have_content("Your card's expiration date is incomplete.")
    end

    it "shows an error with an invalid credit card number" do
      within_frame find('#card_number iframe') do
        '1111 1111 1111 1111'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"
      expect(page).to have_content("Your card number is invalid.")
    end

    it "shows an error with invalid security fields" do
      within_frame find('#card_number iframe') do
        '4242 4242 4242 4242'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '12' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"
      expect(page).to have_content("Your card's security code is incomplete.")
    end

    it "shows an error with invalid expiry fields" do
      within_frame find('#card_number iframe') do
        '4242 4242 4242 4242'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') { fill_in 'exp-date', with: "013" }
      click_button "Save and Continue"
      expect(page).to have_content("Your card's expiration date is incomplete.")
    end
  end

  context 'when using Stripe V3 API libarary with Elements', :js do
    let(:preferred_v3_elements) { true }
    let(:preferred_v3_intents) { false }

    before do
      click_on "Save and Continue"
      expect(page).to have_current_path("/checkout/payment")
    end

    it "can process a valid payment" do
      within_frame find('#card_number iframe') do
        '4242 4242 4242 4242'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")
    end

    it "can re-use saved cards" do
      within_frame find('#card_number iframe') do
        '4242 4242 4242 4242'.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")

      visit spree.root_path
      click_link "DL-44"
      click_button "Add To Cart"

      expect(page).to have_current_path("/cart")
      click_button "Checkout"

      # Address
      expect(page).to have_current_path("/checkout/address")

      within("#billing") do
        fill_in_name
        fill_in "Street Address", with: "YT-1300"
        fill_in "City", with: "Mos Eisley"
        select "United States of America", from: "Country"
        select country.states.first.name, from: "order_bill_address_attributes_state_id"
        fill_in "Zip", with: "12010"
        fill_in "Phone", with: "(555) 555-5555"
      end
      click_on "Save and Continue"

      # Delivery
      expect(page).to have_current_path("/checkout/delivery")
      expect(page).to have_content("UPS Ground")
      click_on "Save and Continue"

      # Payment
      expect(page).to have_current_path("/checkout/payment")
      choose "Use an existing card on file"
      click_button "Save and Continue"

      # Confirm
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")
    end

    it_behaves_like "Stripe Elements invalid payments"
  end

  context "when using Stripe V3 API libarary with Intents", :js do
    let(:preferred_v3_elements) { false }
    let(:preferred_v3_intents) { true }

    before do
      click_on "Save and Continue"
      expect(page).to have_current_path("/checkout/payment")
    end

    context "when using a valid 3D Secure card" do
      let(:card_number) { "4000 0027 6000 3184" }

      it "successfully completes the checkout" do
        within_frame find('#card_number iframe') do
          card_number.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
        end
        within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
        within_frame(find '#card_expiry iframe') do
          '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
        end

        click_button "Save and Continue"

        within_3d_secure_modal do
          expect(page).to have_content '$19.99 using 3D Secure'

          click_button 'Complete authentication'
        end

        expect(page).to have_current_path("/checkout/confirm")

        click_button "Place Order"

        expect(page).to have_content("Your order has been processed successfully")
      end
    end

    context "when using a card without enough money" do
      let(:card_number) { "4000 0000 0000 9995" }

      it "fails the payment" do
        within_frame find('#card_number iframe') do
          card_number.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
        end
        within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
        within_frame(find '#card_expiry iframe') do
          '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
        end

        click_button "Save and Continue"

        expect(page).to have_content "Your card has insufficient funds."
      end
    end

    context "when entering the wrong 3D verification code" do
      let(:card_number) { "4000 0084 0000 1629" }

      it "fails the payment" do
        within_frame find('#card_number iframe') do
          card_number.split('').each { |n| find_field('cardnumber').native.send_keys(n) }
        end
        within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
        within_frame(find '#card_expiry iframe') do
          '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
        end

        click_button "Save and Continue"

        within_3d_secure_modal do
          click_button 'Complete authentication'
        end

        expect(page).to have_content "Your card was declined."
      end
    end

    it "can re-use saved cards" do
      within_frame find('#card_number iframe') do
        "4000 0027 6000 3184".split('').each { |n| find_field('cardnumber').native.send_keys(n) }
      end
      within_frame(find '#card_cvc iframe') { fill_in 'cvc', with: '123' }
      within_frame(find '#card_expiry iframe') do
        '0132'.split('').each { |n| find_field('exp-date').native.send_keys(n) }
      end
      click_button "Save and Continue"

      within_3d_secure_modal do
        click_button 'Complete authentication'
      end

      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")

      visit spree.root_path
      click_link "DL-44"
      click_button "Add To Cart"

      expect(page).to have_current_path("/cart")
      click_button "Checkout"

      # Address
      expect(page).to have_current_path("/checkout/address")

      within("#billing") do
        fill_in_name
        fill_in "Street Address", with: "YT-1300"
        fill_in "City", with: "Mos Eisley"
        select "United States of America", from: "Country"
        select country.states.first.name, from: "order_bill_address_attributes_state_id"
        fill_in "Zip", with: "12010"
        fill_in "Phone", with: "(555) 555-5555"
      end
      click_on "Save and Continue"

      # Delivery
      expect(page).to have_current_path("/checkout/delivery")
      expect(page).to have_content("UPS Ground")
      click_on "Save and Continue"

      # Payment
      expect(page).to have_current_path("/checkout/payment")
      choose "Use an existing card on file"
      click_button "Save and Continue"

      # Confirm
      expect(page).to have_current_path("/checkout/confirm")
      click_button "Place Order"
      expect(page).to have_content("Your order has been processed successfully")
    end

    it_behaves_like "Stripe Elements invalid payments"
  end

  def within_3d_secure_modal
    within_frame "__privateStripeFrame10" do
      within_frame "challengeFrame" do
        yield
      end
    end
  end
end

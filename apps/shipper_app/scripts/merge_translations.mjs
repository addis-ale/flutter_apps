// One-shot merge of the Next.js shipper's per-namespace JSONs into a single
// nested JSON per locale, for `easy_localization`. Run from anywhere:
//
//   node flutter_apps/apps/shipper_app/scripts/merge_translations.mjs
//
// Output goes to flutter_apps/apps/shipper_app/assets/translations/*.json.
// Idempotent — safe to re-run after changes to the upstream locale files.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(HERE, '../../../../shipper/src/i18n/locales');
const DST = resolve(HERE, '../assets/translations');

const LOCALES = ['en', 'am', 'om', 'so', 'ti'];
const NAMESPACES = [
  'auth',
  'common',
  'container',
  'dashboard',
  'organization',
  'shipment',
  'validation',
];

// Reset-password keys that live as inline `defaultValue` in the Next.js
// code but never made it into the upstream JSONs. Added to English; other
// locales fall back via useFallbackTranslations.
const ENGLISH_PATCHES = (locale) => {
  if (locale !== 'en') return {};
  return {
    auth: {
      reset_password: {
        resend_success: 'A new code has been sent to your email.',
        resend_in: 'Resend in {seconds}s',
        sending: 'Sending...',
        didnt_get_code: "Didn't get the code? Resend",
        request_new_code: 'Request a new code',
      },
      welcome: {
        login: 'Login',
        intro_title: 'Wetruck Shipper',
        intro_desc:
            'Your shipper portal for managing freight from request to delivery.',
        slide1_title: 'Create shipments',
        slide1_desc: 'Set your route, cargo and containers, then request a price.',
        slide2_title: 'Compare & accept',
        slide2_desc: 'Review transporter quotes and bids, and pick the best one.',
        slide3_title: 'Track in real time',
        slide3_desc: 'Follow every container from pickup to delivery.',
      },
    },
    shipment: {
      search_placeholder: 'Search by tracking number, origin, destination…',
      no_match: 'No shipments match your search.',
      tabs: {
        all: 'All',
        accepted_by_shipper: 'Accepted',
        rejected_by_shipper: 'Rejected',
        allocated: 'Allocated',
        ready_for_pickup: 'Ready for Pickup',
        in_transit: 'In Transit',
        delivered: 'Delivered',
        completed: 'Completed',
      },
      detail: {
        origin: 'Origin',
        destination: 'Destination',
        pickup: 'Pickup',
        delivery: 'Delivery',
        phone: 'Phone',
        email: 'Email',
        address: 'Address',
        region_country: 'Region / Country',
        track_shipment: 'Track Shipment',
        view_tracking: 'View Tracking',
        view_quotes: 'View Accepted Quote',
        review_quotes: 'Review Quotes',
        view_documents: 'View Documents',
        edit_shipment: 'Edit shipment',
        delete_shipment: 'Delete shipment',
        delete_confirm_title: 'Delete this shipment?',
        delete_confirm_description:
            'Shipment #{id} and any draft details will be permanently removed. This can’t be undone.',
        deleted: 'Shipment #{id} deleted',
        delete_failed: 'Failed to delete shipment',
        delete_restricted:
            'Shipment can’t be deleted while it’s “{status}”.',
        request_price: 'Request price',
        request_price_cta: 'Request',
        request_price_hint:
            'Add at least one container and an approved Bill of Lading and Packing List before requesting a price.',
        request_price_confirm_title: 'Request a price for this shipment?',
        request_price_confirm_description:
            'Our team will review your containers and documents and send transporter quotes. You won’t be able to edit this shipment afterwards.',
        request_price_success: 'Price requested — quotes will appear here soon.',
        request_price_failed: 'Failed to request price',
      },
      create_form: {
        created: 'Shipment #{id} created',
        step_progress: 'Step {current} of {total} — {label}',
        steps: {
          route_dates_hint: 'Where the shipment moves between and when',
          pickup_address_hint:
              'Where will the cargo be picked up from?',
          delivery_address_hint:
              'Where should the cargo be delivered to?',
        },
      },
      update_form: {
        updated: 'Shipment #{id} updated',
      },
      documents: {
        empty_hint: 'Upload the Bill of Lading, Packing List, or other shipment paperwork to keep everything in one place.',
        delete_title: 'Delete this document?',
        delete_description: 'The file will be removed from this shipment. You can re-upload it later if needed.',
        read_failed: 'Could not read the selected file. Please try again.',
        open_failed: 'Could not open the document. Please try again.',
        failed_to_load: 'Failed to load documents',
        viewer_failed: 'Could not display this document.',
        unsupported: "This file can't be previewed in the app. Open it externally instead.",
        open_external: 'Open externally',
        view_document: 'View document',
        replace: 'Replace',
        replace_success: 'Document replaced',
        replace_failed: 'Failed to replace document',
        edit_locked: 'The Bill of Lading and Packing List can only be added or removed while the shipment is in the Created stage.',
        status: {
          approved: 'Approved',
          pending: 'Pending',
          rejected: 'Rejected',
          in_active: 'Inactive',
          expired: 'Expired',
        },
      },
      quotes: {
        title: 'Quotes for shipment #{id}',
        subtitle: 'Compare prices from transporters and accept one to lock in delivery.',
        total_quotes: 'Quotes',
        transporters: 'Transporters',
        total_containers: 'Containers',
        transporter: 'Transporter #{id}',
        containers_count: '{count} containers',
        containers_breakdown: 'Containers in this quote',
        bundle: 'Bundle #{id}',
        accept_quote: 'Accept this quote',
        accepting: 'Accepting…',
        already_accepted: 'Already accepted',
        accepted: 'Quote accepted successfully',
        accept_failed: 'Failed to accept quote',
        failed_to_load: 'Failed to load quotes',
        confirm_title: 'Accept this transporter’s quote?',
        confirm_description: 'Once accepted, transporter #{id} will be awarded the shipment and other quotes will be closed.',
        price_label: 'Total price',
        containers_label: 'Containers',
        no_quotes_title: 'No quotes yet',
        no_quotes_hint: 'Once your shipment is priced by our team, the transporter quotes will appear here for you to choose.',
      },
      containers: {
        no_assigned: 'No containers assigned',
        title: 'Containers',
        nav_subtitle: 'Create and manage your containers',
        total_label: 'Total containers',
        search: 'Search by container number',
        no_found: 'No containers found',
        no_found_hint: 'Create your first container to get started.',
        add: 'Add container',
        new_container: 'New container',
        update_title: 'Edit container',
        update_success: 'Container updated',
        update_failed: 'Failed to update container',
        edit: 'Edit',
        delete: 'Delete',
        add_options_title: 'Add a container',
        add_options_create: 'Create a new container',
        add_options_create_hint: 'Enter details for a brand-new container.',
        add_options_select: 'Select existing containers',
        add_options_select_hint: 'Choose from containers you already created.',
        assign_title: 'Available containers',
        assign_desc: 'Select one or more containers to add to this shipment.',
        assign_search: 'Search by container number',
        assign_none: 'No available containers to assign.',
        assign_no_match: 'No containers match your search.',
        assign_button: 'Assign {count} container(s)',
        assign_select_all: 'Select all',
        assign_success: 'Containers assigned',
        assign_failed: 'Failed to assign containers',
        available_count: '{count} available',
        detail_title: 'Container details',
        specifications: 'Specifications',
        weight_details: 'Weight',
        cargo_info: 'Cargo',
        recommendations: 'Recommendation',
        sequencing_priority: 'Sequencing priority',
        recommended_truck: 'Recommended truck type',
        weight_gross: 'Gross weight',
        weight_tare: 'Tare weight',
        no_cargo: 'No cargo details added.',
        delete_confirm_title: 'Delete this container?',
        delete_confirm_description: 'Container {number} will be permanently deleted. This cannot be undone.',
        deleted: 'Container deleted',
        delete_failed: 'Failed to delete container',
        empty_title: 'No containers yet',
        empty_hint: 'Add the containers for this shipment so it can be priced.',
        edit_locked: 'Containers can only be added or removed while the shipment is in the Created stage.',
        count: '{count} container(s)',
        remove: 'Remove',
        remove_confirm_title: 'Remove this container?',
        remove_confirm_description: 'Container {number} will be detached from this shipment. The container itself is kept.',
        removed: 'Container removed',
        remove_failed: 'Failed to remove container',
        created: 'Container added',
        create_failed: 'Failed to add container',
        section_basic: 'Container details',
        section_cargo: 'Cargo',
        section_return: 'Return location',
        number: 'Container number',
        size: 'Size',
        type: 'Type',
        gross_weight: 'Gross weight (kg)',
        tare_weight: 'Tare weight (kg, optional)',
        truck_type: 'Recommended truck type (optional)',
        is_returning: 'Returning container',
        is_returning_hint: 'The empty container must be returned after delivery.',
        instruction: 'Handling instruction',
        commodity: 'Commodity',
        add_commodity: 'Add commodity',
        country: 'Country',
        city: 'City',
        port: 'Port',
        address: 'Address',
        select_size: 'Select size',
        select_type: 'Select type',
        select_truck_type: 'Select truck type',
        select_country: 'Select country',
      },
      tracking: {
        last_known_position: 'Last known position',
        last_update: 'Last update',
        speed: 'Speed',
        heading: 'Heading',
        latitude: 'Latitude',
        longitude: 'Longitude',
        copy_position: 'Copy coordinates',
        view_on_map: 'View on map',
      },
      bids: {
        accepted: 'Bid accepted',
        accept_failed: 'Failed to accept bid',
        transporter: 'Transporter',
      },
      ship_item: {
        manage: 'Documents & rating',
        list_title: 'Your ship items',
        list_subtitle: 'View transporter documents, upload proof of payment, and rate the transporter.',
        empty: 'No ship items yet.',
        title: 'Ship item #{id}',
        transporter: 'Transporter #{id}',
        documents: 'Documents',
        no_documents: 'No documents yet.',
        proof_of_payment: 'Proof of payment',
        upload_proof: 'Upload proof of payment',
        proof_uploaded: 'Proof of payment uploaded',
        proof_success: 'Proof of payment uploaded',
        proof_failed: 'Failed to upload proof of payment',
        rate_transporter: 'Rate transporter',
        your_rating: 'Your rating',
        rate_comment: 'Comment (optional)',
        submit_rating: 'Submit rating',
        rating_submitted: 'Thanks for your rating',
        rating_failed: 'Failed to submit rating',
        after_delivery: 'Available once the ship item is delivered.',
        view: 'View',
      },
      open_for_bid: {
        title: 'Open bids',
        nav_subtitle: 'Items open for transporter bidding',
        subtitle: 'Ship items you’ve opened for transporters to bid on.',
        route: 'Route',
        pickup: 'Pickup',
        delivery: 'Delivery',
        price: 'Price',
        containers: '{count} container(s)',
        view_bids: 'View bids',
        empty_title: 'No items open for bid',
        empty_hint: 'When a ship item is open for bidding, it’ll appear here.',
        failed_to_load: 'Failed to load open bid items',
      },
    },
    common: {
      actions: {
        copied: 'Copied to clipboard',
        copy: 'Copy',
      },
    },
    organization: {
      nav_title: 'Organization documents',
      nav_subtitle: 'Trade licence & company documents',
      empty_title: 'No documents yet',
      empty_hint:
          'Upload your trade licence and company documents to keep them on file.',
      one_per_type_hint:
          'You can keep one active document per type. Delete the existing one to replace it.',
    },
    nav: {
      home: 'Home',
      shipments: 'Shipments',
      containers: 'Containers',
      bids: 'Bids',
      more: 'More',
    },
    more: {
      language: 'Language',
      change_password: 'Change password',
      sign_out_confirm_title: 'Sign out?',
      sign_out_confirm_description:
          'You’ll need to sign in again to access your account.',
    },
    validation: {
      password_weak:
          'Must include uppercase, lowercase, a digit, and a special character (@\$!%*?&#)',
      password_same_as_current:
          'New password must be different from your current password',
    },
    dashboard: {
      greeting: 'Hi, {name} 👋',
      total_shipments: 'Shipments',
      open_bids: 'Open bids',
      quick_actions: 'Quick actions',
      new_shipment: 'New shipment',
      see_all: 'See all',
    },
  };
};

function deepMerge(target, patch) {
  for (const [k, v] of Object.entries(patch)) {
    if (
      v &&
      typeof v === 'object' &&
      !Array.isArray(v) &&
      target[k] &&
      typeof target[k] === 'object'
    ) {
      deepMerge(target[k], v);
    } else {
      target[k] = v;
    }
  }
  return target;
}

// i18next-style {{name}} → easy_localization {name}.
function convertInterpolation(obj) {
  if (typeof obj === 'string') {
    return obj.replace(/\{\{\s*([^}\s]+)\s*\}\}/g, '{$1}');
  }
  if (Array.isArray(obj)) return obj.map(convertInterpolation);
  if (obj && typeof obj === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(obj)) out[k] = convertInterpolation(v);
    return out;
  }
  return obj;
}

// Onboarding (welcome) copy per locale. English comes from ENGLISH_PATCHES;
// these are translations so switching language reflects on the welcome screen.
// `intro_title` keeps the "Wetruck Shipper" brand name in all locales.
// NOTE: best-effort translations — worth a native-speaker review.
const WELCOME_I18N = {
  am: {
    login: 'ግባ',
    intro_title: 'Wetruck Shipper',
    intro_desc: 'ጭነትዎን ከጥያቄ እስከ ማድረስ የሚያስተዳድሩበት የላኪ መተግበሪያ።',
    slide1_title: 'ጭነት ይፍጠሩ',
    slide1_desc: 'መንገድ፣ ጭነትና ኮንቴይነሮችን ያስገቡ፤ ከዚያ ዋጋ ይጠይቁ።',
    slide2_title: 'ያወዳድሩ እና ይቀበሉ',
    slide2_desc: 'የአጓጓዦችን ዋጋና ጨረታዎች ይገምግሙ፤ ምርጡን ይምረጡ።',
    slide3_title: 'በቀጥታ ይከታተሉ',
    slide3_desc: 'እያንዳንዱን ኮንቴይነር ከመነሻ እስከ መድረሻ ይከታተሉ።',
  },
  om: {
    login: 'Seeni',
    intro_title: 'Wetruck Shipper',
    intro_desc: "Fe'umsa kee gaaffii irraa hanga geejjibaatti bakka tokkotti kan ittiin bulchitu.",
    slide1_title: "Fe'umsa uumi",
    slide1_desc: "Daandii, fe'umsaa fi koonteenaroota galchi; ergasii gatii gaafadhu.",
    slide2_title: 'Wal bira qabii fudhadhu',
    slide2_desc: 'Gatii fi caalbaasii geejjibsiiftotaa ilaalii, isa gaarii filadhu.',
    slide3_title: 'Yeroo dhugaatti hordofi',
    slide3_desc: "Koonteenara hunda ka'umsa irraa hanga geejjibaatti hordofi.",
  },
  so: {
    login: 'Gal',
    intro_title: 'Wetruck Shipper',
    intro_desc: 'Boggaaga dirista ee aad kaga maamushid xamuulkaaga laga bilaabo codsiga ilaa gaarsiinta.',
    slide1_title: 'Abuur shixnado',
    slide1_desc: 'Geli waddada, xamuulka iyo weelasha, ka dibna codso qiime.',
    slide2_title: 'Isbarbar dhig oo aqbal',
    slide2_desc: 'Eeg qiimaha iyo dalabaadka gaadiidleyda, dooro kan ugu fiican.',
    slide3_title: 'La soco waqtiga dhabta ah',
    slide3_desc: 'La soco weel kasta laga bilaabo qaadista ilaa gaarsiinta.',
  },
  ti: {
    login: 'እቶ',
    intro_title: 'Wetruck Shipper',
    intro_desc: 'ንጽዕነትኩም ካብ ሕቶ ክሳብ ምብጻሕ እትመሓድሩሉ መተግበሪ ላኣኺ።',
    slide1_title: 'ጽዕነት ፍጠሩ',
    slide1_desc: 'መገዲ፣ ጽዕነትን ኮንተይነራትን ኣእትዉ፤ ሽዑ ዋጋ ሕተቱ።',
    slide2_title: 'ኣነጻጽሩን ተቐበሉን',
    slide2_desc: 'ዋጋን ጨረታን ኣጓዓዝቲ ገምግሙ፤ ዝበለጸ ምረጹ።',
    slide3_title: 'ብቐጥታ ተኸታተሉ',
    slide3_desc: 'ንነፍሲ ወከፍ ኮንተይነር ካብ መልዓል ክሳብ ምብጻሕ ተኸታተሉ።',
  },
};

let total = 0;
for (const locale of LOCALES) {
  const merged = {};
  for (const ns of NAMESPACES) {
    const text = readFileSync(join(SRC, locale, `${ns}.json`), 'utf8');
    // Strip UTF-8 BOM if present.
    const clean = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
    merged[ns] = JSON.parse(clean);
  }
  deepMerge(merged, ENGLISH_PATCHES(locale));
  if (WELCOME_I18N[locale]) {
    deepMerge(merged, { auth: { welcome: WELCOME_I18N[locale] } });
  }
  const converted = convertInterpolation(merged);
  const outPath = join(DST, `${locale}.json`);
  // Stringify with 2-space indent and write as plain UTF-8 (no BOM —
  // Node's writeFileSync never adds one).
  writeFileSync(outPath, JSON.stringify(converted, null, 2), 'utf8');
  total += 1;
  console.log(`wrote ${outPath}`);
}

console.log(`\nMerged ${total} locale${total === 1 ? '' : 's'}.`);

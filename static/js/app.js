/* Work Log - keeps the Gregorian date picker and the Jalali text field in sync. */
(function () {
  "use strict";

  var gregInput = document.getElementById("gregorian_date");
  var jalaliInput = document.getElementById("jalali_date");
  var hint = document.getElementById("date-hint");
  var form = document.getElementById("log-form");

  if (!gregInput || !jalaliInput) {
    return;
  }

  var syncing = false;
  var timer = null;

  function setHint(text, isError) {
    if (!hint) {
      return;
    }
    hint.textContent = text;
    hint.classList.toggle("text-rose-500", !!isError);
    hint.classList.toggle("text-slate-400", !isError);
  }

  function markInvalid(el, invalid) {
    if (!el) {
      return;
    }
    el.classList.toggle("border-rose-300", !!invalid);
    el.classList.toggle("ring-4", !!invalid);
    el.classList.toggle("ring-rose-100", !!invalid);
  }

  function convert(params) {
    var qs = Object.keys(params)
      .map(function (key) {
        return encodeURIComponent(key) + "=" + encodeURIComponent(params[key]);
      })
      .join("&");

    return fetch("/api/dates/convert?" + qs, {
      headers: { Accept: "application/json" }
    }).then(function (response) {
      return response.json().then(function (body) {
        return { ok: response.ok && body.ok, body: body };
      });
    });
  }

  function fromGregorian() {
    if (syncing || !gregInput.value) {
      return;
    }
    syncing = true;
    convert({ gregorian: gregInput.value })
      .then(function (result) {
        if (!result.ok) {
          markInvalid(gregInput, true);
          setHint("تاریخ میلادی نامعتبر است", true);
          return;
        }
        markInvalid(gregInput, false);
        markInvalid(jalaliInput, false);
        jalaliInput.value = result.body.jalali;
        setHint(result.body.jalali_long, false);
      })
      .catch(function () {
        /* offline: leave the fields as they are */
      })
      .then(function () {
        syncing = false;
      });
  }

  function fromJalali() {
    if (syncing || !jalaliInput.value.trim()) {
      return;
    }
    syncing = true;
    convert({ jalali: jalaliInput.value.trim() })
      .then(function (result) {
        if (!result.ok) {
          markInvalid(jalaliInput, true);
          setHint("تاریخ شمسی را به شکل ۱۴۰۵/۰۸/۱۸ وارد کنید", true);
          return;
        }
        markInvalid(jalaliInput, false);
        markInvalid(gregInput, false);
        gregInput.value = result.body.gregorian;
        setHint(result.body.jalali_long, false);
      })
      .catch(function () {
        /* ignore network hiccups */
      })
      .then(function () {
        syncing = false;
      });
  }

  function debounce(fn, wait) {
    return function () {
      if (timer) {
        clearTimeout(timer);
      }
      timer = setTimeout(fn, wait);
    };
  }

  gregInput.addEventListener("change", fromGregorian);
  gregInput.addEventListener("input", debounce(fromGregorian, 250));
  jalaliInput.addEventListener("change", fromJalali);
  jalaliInput.addEventListener("input", debounce(fromJalali, 400));

  if (form) {
    form.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        form.requestSubmit();
      }
    });
  }
})();

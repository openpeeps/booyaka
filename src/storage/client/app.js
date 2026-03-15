/**
 * Booyaka Client App
 * 
 * This module initializes the client-side application, sets up UI interactions,
 * and provides utility functions for features like sticky sidebars and "time ago" formatting.
 */
const defaultAppOpts = {
  /**
   * Enable sticky sidebars that remain visible below the navbar when scrolling.
   * This is useful for keeping navigation or other important elements accessible.
   */
  enableStickySidebar: true,

  /**
   * Enable "time ago" formatting for <time> elements with a datetime attribute.
   * This converts timestamps into a human-readable format like "5 minutes ago".
   * It enhances the user experience by providing relative time information.
  */
  enableTimeAgo: true,

  /**
   * Enable animated alerts that follow the mouse cursor within the alert box.
   * This adds a dynamic visual effect to alert messages, making them more engaging.
   * The animation allows the alert to move slightly in response to mouse movements,
   * creating an interactive experience for the user.
  */
  enableAnimatedAlerts: true
}

export default {
  /**
   * Initialize the application with the given options.
   * This function sets up the UI features based on the provided options.
   * It also adds necessary event listeners and applies styles to checkboxes.
   * 
   * @param {Object} opts - Configuration options for initializing the app.
   * @param {boolean} opts.enableStickySidebar - Whether to enable sticky sidebars.
   * @param {boolean} opts.enableTimeAgo - Whether to enable "time ago" formatting.
   * @param {callback} opts.fetchAndSwapCallback - Optional callback to override the default fetchAndSwap behavior.
   *
  */
  init: function(opts = defaultAppOpts) {
    console.log("Booyaka Initialized");
    if (opts.enableStickySidebar) this.initStickySidebar();
    if (opts.enableTimeAgo) this.initTimeAgo();
    if (opts.enableAnimatedAlerts) this.initAnimatedAlerts();
    this.initSmoothAnchors();
    this.initExternalLinksDecorator();

    // Intercept clicks on internal links to enable SPA-like navigation without full page reloads.
    let sidebarNavigation = document.querySelector('.sidebar-navigation')
    document.addEventListener('click', (e) => {
      const a = e.target.closest('a');
      if (a &&  a.href &&  a.origin === location.origin && !a.hasAttribute('download') && 
        !a.target &&  !a.href.startsWith('mailto:') &&  !a.href.startsWith('tel:') && !a.getAttribute('href').startsWith('#')) {
        e.preventDefault();
        // checking if the clicked element is part of the navigaiton menu
        // if so, we want to make the clicked item active and remove active from others
        if (sidebarNavigation && sidebarNavigation.contains(a)) {
          sidebarNavigation.querySelectorAll('a').forEach(link => link.classList.remove('active', 'bg-dark'));
          a.classList.add('active', 'bg-dark');
        }
        this.fetchAndSwap(a.pathname + a.search, true, opts.fetchAndSwapCallback);
      }
    });

    document.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
      checkbox.classList.add('form-check-input'); // the bootstrap class
    });
  },
  
  /**
   * Make sidebars sticky so they remain visible when scrolling down the page.
   */
  initStickySidebar: function() {
    const sidebars = document.querySelectorAll('.sticky-sidebar');
    const navbarHeight = document.querySelector('.navbar-container-area').offsetHeight;
    const extraPadding = 30; // px, adjust for pt-5 effect

    function updateSidebarTop() {
      for (const sidebar of sidebars) {
        const scrollY = window.scrollY || window.pageYOffset;
        sidebar.style.top = (navbarHeight + extraPadding) + 'px';
      }
    }
    window.addEventListener('scroll', updateSidebarTop);
    window.addEventListener('resize', updateSidebarTop);
    updateSidebarTop()
  },

  /**
   * Initialize smooth scrolling for internal anchor links.
   * This function ensures that when users click on links that point to anchors within the page,
   * the page will scroll smoothly to the target section, accounting for the height of the sticky navbar.
   */
  initSmoothAnchors: function() {
    // Smooth scroll to anchor, offset by sticky navbar height
    function scrollToAnchorWithOffset(hash) {
      const navbar = document.querySelector('.navbar-container-area');
      const navbarHeight = navbar ? navbar.offsetHeight : 0;
      const target = document.getElementById(hash);
      console.log(target)
      if (target) {
        const targetPosition = target.getBoundingClientRect().top + window.pageYOffset;
        window.scrollTo({
          top: targetPosition - navbarHeight,
          behavior: 'smooth'
        });
      }
    }

    // Attach click event to all internal anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      anchor.addEventListener('click', function(e) {
        const rawHash = this.getAttribute('href');
        const hash = decodeURIComponent(rawHash.slice(1));
        if (hash) {
          const target = document.getElementById(hash) || document.querySelector(`[name="${hash}"]`);
          if (target) {
            e.preventDefault();
            scrollToAnchorWithOffset(hash);
            history.replaceState(null, null, rawHash);
          }
        }
      });
    });

    // If page loads with a hash, scroll to it with offset
    if (window.location.hash) {
      setTimeout(() => {
        const hash = window.location.hash.slice(1);
        scrollToAnchorWithOffset(hash);
      }, 100);
    }
  },


  /**
   * Fetches the given URL and swaps the content of the current
   * view with the new view from the response.
   * 
   * If the fetch fails or the expected view container is not
   * found in the response, it falls back to a full page reload.
   * 
   * @param {string} url - The URL to fetch and swap.
   * @param {boolean} pushState - Whether to push the new URL to the browser history (default: true).
   * @param {callback} callback - Optional callback to execute after successful content swap.
   * @returns {void}
  */
  fetchAndSwap(url, pushState = true, callback) {
    fetch(url, {headers: {'X-Requested-With': 'spa'}})
      .then(resp => {
        if (!resp.ok) throw new Error('Network error');
        return resp.text();
      })
      .then(html => {
        // parse the returned HTML and extract the new view
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newView = doc.querySelector('[data-view]');
        const currentView = document.querySelector('[data-view]');
        if (newView && currentView) {
          currentView.innerHTML = newView.innerHTML;
          if (pushState) history.pushState(null, '', url);
          window.scrollTo(0, 0);
          callback && callback(url, newView);
        } else {
          console.warn('Could not find view container in the fetched HTML. Reloading the page as fallback.');
          location.href = url;
        }
      }).catch(() => location.href = url);
  },

  initExternalLinksDecorator: function() {
    // Function to check if a link is external
    function isExternalLink(anchor) {
      return anchor.hostname && anchor.hostname !== window.location.hostname;
    }

    // Example: Add 'external' class to all external links
    document.querySelectorAll('a[href]').forEach(a => {
      if (isExternalLink(a)) {
        a.classList.add('external');
        a.setAttribute('target', '_blank');
      }
    });
  },

  /**
   * Initialize the application with the default options.
   */
  initAnimatedAlerts: function() {
    document.querySelectorAll('.alert').forEach(alert => {
      const anim = document.createElement('div');
      anim.className = 'alert-animation';
      anim.style.left = '0px';
      anim.style.top = '0px';
      alert.style.position = 'relative';
      alert.insertAdjacentElement('afterbegin', anim);

      // Set your desired offset here
      const offsetX = 400; // pixels allowed to exceed horizontally
      const offsetY = 400; // pixels allowed to exceed vertically

      document.body.addEventListener('mousemove', e => {
        const rect = alert.getBoundingClientRect();
        const animW = anim.offsetWidth;
        const animH = anim.offsetHeight;
        let x = e.clientX - rect.left - animW / 2;
        let y = e.clientY - rect.top - animH / 2;

        // Allow exceeding by offset
        x = Math.max(-offsetX, Math.min(x, rect.width - animW + offsetX));
        y = Math.max(-offsetY, Math.min(y, rect.height - animH + offsetY));

        // Calculate rotation based on mouse position (example: angle from center)
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        const dx = x + animW / 2 - centerX;
        const dy = y + animH / 2 - centerY;
        const angle = Math.atan2(dy, dx) * (18 / Math.PI); // degrees
        anim.style.transform = 'translate(' + x + 'px, ' + y + 'px) rotate(' + angle + 'deg)';
      });
    });
  },
  
  /**
   * Initialize "time ago" formatting for <time> elements.
   * 
   * Convert a date string into a "time ago" format.
   * Example: "2023-10-01 12:00:00" -> "5 minutes ago"
   */
  initTimeAgo: function() {
    function timeago(dateString) {
      const timeStrings = {
        minute: ["minute", "minutes"],
        hour: ["hour", "hours"],
        day: ["day", "days"],
      };
      
      function pluralize(unit, value) {
        return value === 1 ? timeStrings[unit][0] : timeStrings[unit][1];
      }
      const date = new Date(dateString.replace(' ', 'T'));
      const now = new Date();
      const diffMs = now - date;
      const diffSec = Math.floor(diffMs / 1000);
      const diffMin = Math.floor(diffSec / 60);
      const diffHour = Math.floor(diffMin / 60);
      const diffDay = Math.floor(diffHour / 24);

      if (diffSec < 60) return "just now";
      if (diffMin < 60) return diffMin + " " + pluralize("minute", diffMin) + " ago";
      if (diffHour < 24) return diffHour + " " + pluralize("hour", diffHour) + " ago";
      return diffDay + " " + pluralize("day", diffDay) + " ago";
    }
    document.querySelectorAll('time[datetime]').forEach(span => {
      span.textContent = timeago(span.getAttribute('datetime'));
    });
  }
}

document.addEventListener('DOMContentLoaded', () => {
  UI.init({
    enableStickySidebar: true,
    enableTimeAgo: true,
    fetchAndSwapCallback: (url, html) => {
      hljs.highlightAll();
    }
  });

  // Initial syntax highlighting for code blocks
  hljs.highlightAll();

  const toggleAreaBtns = document.querySelectorAll('button[data-toggle-area]');
  const mainArea = document.querySelector('div[data-area="main"]');
  const leftSidebar = document.querySelector('div[data-area="left"]');
  const rightSidebar = document.querySelector('div[data-area="right"]');

  // Load preferences from localStorage
  let isLeftSidebarVisible = localStorage.getItem('leftSidebarVisible') !== 'false';
  let isRightSidebarVisible = localStorage.getItem('rightSidebarVisible') !== 'false';

  function updateMainAreaCols() {
    if (!isLeftSidebarVisible && !isRightSidebarVisible) {
      mainArea.classList.remove('col-lg-7', 'col-lg-9');
      mainArea.classList.add('col-lg-12');
    } else if (!isLeftSidebarVisible || !isRightSidebarVisible) {
      mainArea.classList.remove('col-lg-7', 'col-lg-12');
      mainArea.classList.add('col-lg-9');
    } else {
      mainArea.classList.remove('col-lg-9', 'col-lg-12');
      mainArea.classList.add('col-lg-7');
    }
  }

  function updateSidebarVisibility() {
    if (isLeftSidebarVisible) {
      leftSidebar.classList.remove('d-none');
      leftSidebar.classList.add('d-lg-block');
    } else {
      leftSidebar.classList.remove('d-lg-block');
      leftSidebar.classList.add('d-none');
    }
    if (isRightSidebarVisible) {
      rightSidebar.classList.remove('d-none');
      rightSidebar.classList.add('d-lg-block');
    } else {
      rightSidebar.classList.remove('d-lg-block');
      rightSidebar.classList.add('d-none');
    }
  }

  toggleAreaBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const areaName = btn.getAttribute('data-toggle-area');
      const areaElement = document.querySelector(`div[data-area="${areaName}"]`);
      const icon = btn.querySelectorAll('span');
      if (areaElement.classList.contains('d-lg-block')) {
        areaElement.classList.remove('d-lg-block');
        areaElement.classList.add('d-none');
        if (areaName === 'left') {
          isLeftSidebarVisible = false;
          localStorage.setItem('leftSidebarVisible', 'false');
        } else if (areaName === 'right') {
          isRightSidebarVisible = false;
          localStorage.setItem('rightSidebarVisible', 'false');
        }
      } else {
        areaElement.classList.remove('d-none');
        areaElement.classList.add('d-lg-block');
        if (areaName === 'left') {
          isLeftSidebarVisible = true;
          localStorage.setItem('leftSidebarVisible', 'true');
        } else if (areaName === 'right') {
          isRightSidebarVisible = true;
          localStorage.setItem('rightSidebarVisible', 'true');
        }
      }
      updateMainAreaCols();
      // Optionally toggle icons here
      icon[0].classList.toggle('d-none');
      icon[1].classList.toggle('d-none');
    });
  });

  // Initial setup
  updateSidebarVisibility();
  updateMainAreaCols();
});
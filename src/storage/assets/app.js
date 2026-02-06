
const defaultAppOpts = {
  enableStickySidebar: true,
  enableTimeAgo: true
}

const Application = {
  init: function(opts = defaultAppOpts) {
    console.log("Booyaka Initialized");
    if (opts.enableStickySidebar) this.initStickySidebar();
    if (opts.enableTimeAgo) this.initTimeAgo();
    this.initSmoothAnchors();
    this.initExternalLinksDecorator();

    document.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
      checkbox.classList.add('form-check-input'); // the bootstrap class
    });
  },
  
  /**
   * Make sidebars sticky below the navbar
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

  initSmoothAnchors: function() {
    // Smooth scroll to anchor, offset by sticky navbar height
    function scrollToAnchorWithOffset(hash) {
      const navbar = document.querySelector('.navbar-container-area');
      const navbarHeight = navbar ? navbar.offsetHeight : 0;
      const target = document.getElementById(hash);
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
        const hash = this.getAttribute('href').slice(1);
        if (document.getElementById(hash)) {
          e.preventDefault();
          scrollToAnchorWithOffset(hash);
          history.replaceState(null, null, '#' + hash);
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
  Application.init();

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
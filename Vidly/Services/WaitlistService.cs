using System;
using System.Collections.Generic;
using System.Linq;
using Vidly.Models;

namespace Vidly.Services
{
    /// <summary>
    /// Manages movie waitlists: join/leave queues, position tracking,
    /// estimated wait times, priority ordering for premium members,
    /// auto-notification on return, history, and demand scoring.
    /// </summary>
    public class WaitlistService
    {
        private readonly List<WaitlistEntry> _entries = new List<WaitlistEntry>();
        private readonly List<WaitlistNotification> _notifications = new List<WaitlistNotification>();
        private readonly List<Customer> _customers;
        private readonly List<Movie> _movies;

        private int _nextEntryId = 1;
        private int _nextNotificationId = 1;

        /// <summary>
        /// Maximum number of customers allowed on a single movie's waitlist.
        /// Set to 0 for unlimited.
        /// </summary>
        public int MaxWaitlistSizePerMovie { get; set; } = 50;

        /// <summary>
        /// Average rental duration in days, used to estimate wait times.
        /// </summary>
        public double AverageRentalDurationDays { get; set; } = 3.0;

        /// <summary>
        /// Number of days after notification before an entry expires automatically.
        /// </summary>
        public int NotificationExpiryDays { get; set; } = 2;

        public WaitlistService(IEnumerable<Customer> customers, IEnumerable<Movie> movies)
        {
            _customers = customers?.ToList()
                ?? throw new ArgumentNullException(nameof(customers));
            _movies = movies?.ToList()
                ?? throw new ArgumentNullException(nameof(movies));
        }

        // ── Join / Leave ──────────────────────────────────────

        /// <summary>
        /// Adds a customer to the waitlist for a movie.
        /// Premium/loyalty members (Gold, Platinum) receive priority placement.
        /// </summary>
        public WaitlistEntry JoinWaitlist(int customerId, int movieId)
        {
            var customer = _customers.FirstOrDefault(c => c.Id == customerId);
            if (customer == null)
                throw new ArgumentException("Customer not found.", nameof(customerId));

            var movie = _movies.FirstOrDefault(m => m.Id == movieId);
            if (movie == null)
                throw new ArgumentException("Movie not found.", nameof(movieId));

            // Duplicate prevention
            var existing = _entries.FirstOrDefault(e =>
                e.CustomerId == customerId && e.MovieId == movieId &&
                (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified));
            if (existing != null)
                throw new InvalidOperationException(
                    $"Customer '{customer.Name}' is already on the waitlist for '{movie.Name}'.");

            // Max size check
            var currentSize = GetActiveCount(movieId);
            if (MaxWaitlistSizePerMovie > 0 && currentSize >= MaxWaitlistSizePerMovie)
                throw new InvalidOperationException(
                    $"Waitlist for '{movie.Name}' is full ({MaxWaitlistSizePerMovie} max).");

            var priority = (customer.MembershipType == MembershipType.Gold ||
                            customer.MembershipType == MembershipType.Platinum)
                ? WaitlistPriority.Premium
                : WaitlistPriority.Standard;

            var entry = new WaitlistEntry
            {
                Id = _nextEntryId++,
                CustomerId = customerId,
                CustomerName = customer.Name,
                MovieId = movieId,
                MovieName = movie.Name,
                JoinedAt = DateTime.Now,
                Status = WaitlistEntryStatus.Active,
                Priority = priority
            };
            _entries.Add(entry);
            return entry;
        }

        /// <summary>
        /// Removes a customer from a movie's waitlist (voluntary leave).
        /// </summary>
        public bool LeaveWaitlist(int customerId, int movieId)
        {
            var entry = _entries.FirstOrDefault(e =>
                e.CustomerId == customerId && e.MovieId == movieId &&
                (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified));
            if (entry == null) return false;

            entry.Status = WaitlistEntryStatus.Cancelled;
            entry.CancelledAt = DateTime.Now;
            return true;
        }

        /// <summary>
        /// Cancels a specific waitlist entry by its ID.
        /// </summary>
        public bool CancelEntry(int entryId)
        {
            var entry = _entries.FirstOrDefault(e => e.Id == entryId);
            if (entry == null || entry.Status == WaitlistEntryStatus.Cancelled ||
                entry.Status == WaitlistEntryStatus.Fulfilled ||
                entry.Status == WaitlistEntryStatus.Expired)
                return false;

            entry.Status = WaitlistEntryStatus.Cancelled;
            entry.CancelledAt = DateTime.Now;
            return true;
        }

        // ── Position Tracking ─────────────────────────────────

        /// <summary>
        /// Returns the 1-based position of a customer in a movie's waitlist,
        /// or -1 if not found. Premium members are ordered before standard members.
        /// </summary>
        public int GetPosition(int customerId, int movieId)
        {
            var ordered = GetOrderedActiveEntries(movieId);
            for (int i = 0; i < ordered.Count; i++)
            {
                if (ordered[i].CustomerId == customerId)
                    return i + 1;
            }
            return -1;
        }

        /// <summary>
        /// Returns the ordered active waitlist for a movie (premium first, then by join time).
        /// </summary>
        public IReadOnlyList<WaitlistEntry> GetWaitlist(int movieId)
        {
            return GetOrderedActiveEntries(movieId);
        }

        /// <summary>
        /// Retrieves a waitlist entry by its ID.
        /// </summary>
        public WaitlistEntry GetEntry(int entryId)
        {
            return _entries.FirstOrDefault(e => e.Id == entryId);
        }

        // ── Wait Time Estimation ──────────────────────────────

        /// <summary>
        /// Estimates the wait time in days for a customer based on their
        /// position and the configured average rental duration.
        /// </summary>
        public double EstimateWaitDays(int customerId, int movieId)
        {
            var position = GetPosition(customerId, movieId);
            if (position < 0)
                throw new InvalidOperationException("Customer is not on this waitlist.");

            return position * AverageRentalDurationDays;
        }

        /// <summary>
        /// Estimates the wait time for a hypothetical new joiner (next position).
        /// </summary>
        public double EstimateWaitDaysForNewJoiner(int movieId)
        {
            var currentSize = GetActiveCount(movieId);
            return (currentSize + 1) * AverageRentalDurationDays;
        }

        // ── Auto-Notify on Return ─────────────────────────────

        /// <summary>
        /// Notifies the next customer in line when a movie is returned.
        /// Returns the notification sent, or null if no one is waiting.
        /// </summary>
        public WaitlistNotification NotifyNextCustomer(int movieId)
        {
            var ordered = GetOrderedActiveEntries(movieId);
            var next = ordered.FirstOrDefault(e => e.Status == WaitlistEntryStatus.Active);
            if (next == null) return null;

            next.Status = WaitlistEntryStatus.Notified;
            next.NotifiedAt = DateTime.Now;

            var movie = _movies.FirstOrDefault(m => m.Id == movieId);
            var notification = new WaitlistNotification
            {
                Id = _nextNotificationId++,
                WaitlistEntryId = next.Id,
                CustomerId = next.CustomerId,
                CustomerName = next.CustomerName,
                MovieId = movieId,
                MovieName = movie?.Name ?? "Unknown",
                NotifiedAt = DateTime.Now,
                Message = $"Great news! '{movie?.Name}' is now available for you to rent."
            };
            _notifications.Add(notification);
            return notification;
        }

        /// <summary>
        /// Marks a notified entry as fulfilled (customer picked up the movie).
        /// </summary>
        public bool FulfillEntry(int entryId)
        {
            var entry = _entries.FirstOrDefault(e => e.Id == entryId);
            if (entry == null || entry.Status != WaitlistEntryStatus.Notified)
                return false;

            entry.Status = WaitlistEntryStatus.Fulfilled;
            entry.FulfilledAt = DateTime.Now;
            return true;
        }

        /// <summary>
        /// Returns all notifications sent for a given movie.
        /// </summary>
        public IReadOnlyList<WaitlistNotification> GetNotifications(int movieId)
        {
            return _notifications
                .Where(n => n.MovieId == movieId)
                .OrderByDescending(n => n.NotifiedAt)
                .ToList();
        }

        // ── Waitlist History ──────────────────────────────────

        /// <summary>
        /// Returns the complete waitlist history for a customer (all statuses).
        /// </summary>
        public IReadOnlyList<WaitlistEntry> GetCustomerHistory(int customerId)
        {
            return _entries
                .Where(e => e.CustomerId == customerId)
                .OrderByDescending(e => e.JoinedAt)
                .ToList();
        }

        /// <summary>
        /// Returns only fulfilled (past) waitlist entries for a customer.
        /// </summary>
        public IReadOnlyList<WaitlistEntry> GetFulfilledHistory(int customerId)
        {
            return _entries
                .Where(e => e.CustomerId == customerId && e.Status == WaitlistEntryStatus.Fulfilled)
                .OrderByDescending(e => e.FulfilledAt)
                .ToList();
        }

        /// <summary>
        /// Returns active waitlist entries for a customer (currently waiting).
        /// </summary>
        public IReadOnlyList<WaitlistEntry> GetActiveEntriesForCustomer(int customerId)
        {
            return _entries
                .Where(e => e.CustomerId == customerId &&
                       (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified))
                .OrderBy(e => e.JoinedAt)
                .ToList();
        }

        // ── Per-Movie Stats ───────────────────────────────────

        /// <summary>
        /// Returns aggregated waitlist statistics for a movie, including
        /// current size, average wait time, and demand score.
        /// </summary>
        public WaitlistStats GetMovieStats(int movieId)
        {
            var movie = _movies.FirstOrDefault(m => m.Id == movieId);
            if (movie == null)
                throw new ArgumentException("Movie not found.", nameof(movieId));

            var active = _entries.Where(e =>
                e.MovieId == movieId &&
                (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified))
                .ToList();

            var resolved = _entries.Where(e =>
                e.MovieId == movieId && e.Status == WaitlistEntryStatus.Fulfilled)
                .ToList();

            var avgWait = resolved.Any()
                ? resolved.Average(e => e.WaitDays)
                : 0.0;

            var maxSize = MaxWaitlistSizePerMovie > 0 ? MaxWaitlistSizePerMovie : 100;
            var demandScore = (double)active.Count / maxSize;

            return new WaitlistStats
            {
                MovieId = movieId,
                MovieName = movie.Name,
                CurrentSize = active.Count,
                PremiumCount = active.Count(e => e.Priority == WaitlistPriority.Premium),
                StandardCount = active.Count(e => e.Priority == WaitlistPriority.Standard),
                AvgWaitTimeDays = Math.Round(avgWait, 2),
                DemandScore = Math.Round(demandScore, 4)
            };
        }

        /// <summary>
        /// Returns stats for all movies that have at least one active waitlist entry,
        /// ordered by demand score descending.
        /// </summary>
        public IReadOnlyList<WaitlistStats> GetAllMovieStats()
        {
            var movieIds = _entries
                .Where(e => e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified)
                .Select(e => e.MovieId)
                .Distinct();

            return movieIds
                .Select(id => GetMovieStats(id))
                .OrderByDescending(s => s.DemandScore)
                .ToList();
        }

        // ── Bulk Operations ───────────────────────────────────

        /// <summary>
        /// Expires notified entries that have been waiting longer than
        /// <see cref="NotificationExpiryDays"/> since notification, then
        /// auto-notifies the next customer for each affected movie.
        /// Returns the number of entries expired.
        /// </summary>
        public int ExpireStaleNotifications()
        {
            var cutoff = DateTime.Now.AddDays(-NotificationExpiryDays);
            var stale = _entries
                .Where(e => e.Status == WaitlistEntryStatus.Notified &&
                            e.NotifiedAt.HasValue && e.NotifiedAt.Value < cutoff)
                .ToList();

            foreach (var entry in stale)
            {
                entry.Status = WaitlistEntryStatus.Expired;
                entry.ExpiredAt = DateTime.Now;

                // Auto-notify the next person in line
                NotifyNextCustomer(entry.MovieId);
            }

            return stale.Count;
        }

        /// <summary>
        /// Removes all cancelled and expired entries older than the specified
        /// number of days. Returns the number of entries purged.
        /// </summary>
        public int PurgeOldEntries(int olderThanDays)
        {
            if (olderThanDays < 0)
                throw new ArgumentException("Days must be non-negative.", nameof(olderThanDays));

            var cutoff = DateTime.Now.AddDays(-olderThanDays);
            var removed = _entries.RemoveAll(e =>
                (e.Status == WaitlistEntryStatus.Cancelled || e.Status == WaitlistEntryStatus.Expired) &&
                e.JoinedAt < cutoff);

            return removed;
        }

        /// <summary>
        /// Clears the entire waitlist for a specific movie, cancelling all
        /// active and notified entries. Returns the number of entries cancelled.
        /// </summary>
        public int ClearMovieWaitlist(int movieId)
        {
            var active = _entries
                .Where(e => e.MovieId == movieId &&
                       (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified))
                .ToList();

            foreach (var entry in active)
            {
                entry.Status = WaitlistEntryStatus.Cancelled;
                entry.CancelledAt = DateTime.Now;
            }

            return active.Count;
        }

        // ── Counts ────────────────────────────────────────────

        /// <summary>Total waitlist entries across all movies and statuses.</summary>
        public int TotalEntries => _entries.Count;

        /// <summary>Total notifications sent.</summary>
        public int TotalNotifications => _notifications.Count;

        // ── Private Helpers ───────────────────────────────────

        private List<WaitlistEntry> GetOrderedActiveEntries(int movieId)
        {
            return _entries
                .Where(e => e.MovieId == movieId &&
                       (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified))
                .OrderByDescending(e => e.Priority)
                .ThenBy(e => e.JoinedAt)
                .ToList();
        }

        private int GetActiveCount(int movieId)
        {
            return _entries.Count(e =>
                e.MovieId == movieId &&
                (e.Status == WaitlistEntryStatus.Active || e.Status == WaitlistEntryStatus.Notified));
        }
    }
}

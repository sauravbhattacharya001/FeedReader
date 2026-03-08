using System;

namespace Vidly.Models
{
    /// <summary>
    /// Represents a single customer waiting for a specific movie.
    /// </summary>
    public class WaitlistEntry
    {
        public int Id { get; set; }
        public int CustomerId { get; set; }
        public string CustomerName { get; set; }
        public int MovieId { get; set; }
        public string MovieName { get; set; }
        public DateTime JoinedAt { get; set; }
        public DateTime? NotifiedAt { get; set; }
        public DateTime? FulfilledAt { get; set; }
        public DateTime? ExpiredAt { get; set; }
        public DateTime? CancelledAt { get; set; }
        public WaitlistEntryStatus Status { get; set; }
        public WaitlistPriority Priority { get; set; }

        /// <summary>
        /// How long this customer has been waiting (or waited before resolution).
        /// </summary>
        public double WaitDays
        {
            get
            {
                var end = FulfilledAt ?? CancelledAt ?? ExpiredAt ?? DateTime.Now;
                return Math.Max(0, (end - JoinedAt).TotalDays);
            }
        }
    }

    /// <summary>
    /// Lifecycle status of a waitlist entry.
    /// </summary>
    public enum WaitlistEntryStatus
    {
        Active = 1,
        Notified = 2,
        Fulfilled = 3,
        Expired = 4,
        Cancelled = 5
    }

    /// <summary>
    /// Priority tier for waitlist ordering.
    /// </summary>
    public enum WaitlistPriority
    {
        Standard = 1,
        Premium = 2
    }

    /// <summary>
    /// Record of a notification sent to a waitlisted customer.
    /// </summary>
    public class WaitlistNotification
    {
        public int Id { get; set; }
        public int WaitlistEntryId { get; set; }
        public int CustomerId { get; set; }
        public string CustomerName { get; set; }
        public int MovieId { get; set; }
        public string MovieName { get; set; }
        public DateTime NotifiedAt { get; set; }
        public string Message { get; set; }
    }

    /// <summary>
    /// Aggregated waitlist statistics for a single movie.
    /// </summary>
    public class WaitlistStats
    {
        public int MovieId { get; set; }
        public string MovieName { get; set; }
        public int CurrentSize { get; set; }
        public int PremiumCount { get; set; }
        public int StandardCount { get; set; }
        public double AvgWaitTimeDays { get; set; }

        /// <summary>
        /// Demand score: ratio of waitlist size to max allowed size (0.0-1.0+).
        /// Higher values indicate stronger demand.
        /// </summary>
        public double DemandScore { get; set; }
    }
}

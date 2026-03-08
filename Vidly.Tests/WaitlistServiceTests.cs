using System;
using System.Collections.Generic;
using System.Linq;
using Vidly.Models;
using Vidly.Services;
using Xunit;

namespace Vidly.Tests
{
    public class WaitlistServiceTests
    {
        private readonly List<Customer> _customers;
        private readonly List<Movie> _movies;
        private readonly WaitlistService _service;

        public WaitlistServiceTests()
        {
            _customers = new List<Customer>
            {
                new Customer { Id = 1, Name = "Alice", MembershipType = MembershipType.Platinum },
                new Customer { Id = 2, Name = "Bob", MembershipType = MembershipType.Basic },
                new Customer { Id = 3, Name = "Carol", MembershipType = MembershipType.Gold },
                new Customer { Id = 4, Name = "Dave", MembershipType = MembershipType.Silver },
                new Customer { Id = 5, Name = "Eve", MembershipType = MembershipType.Basic }
            };
            _movies = new List<Movie>
            {
                new Movie { Id = 10, Name = "Inception" },
                new Movie { Id = 20, Name = "The Matrix" },
                new Movie { Id = 30, Name = "Interstellar" }
            };
            _service = new WaitlistService(_customers, _movies);
        }

        // ── Constructor ───────────────────────────────────────

        [Fact]
        public void Constructor_NullCustomers_Throws()
        {
            Assert.Throws<ArgumentNullException>(() => new WaitlistService(null, _movies));
        }

        [Fact]
        public void Constructor_NullMovies_Throws()
        {
            Assert.Throws<ArgumentNullException>(() => new WaitlistService(_customers, null));
        }

        [Fact]
        public void Constructor_EmptyLists_Works()
        {
            var svc = new WaitlistService(new List<Customer>(), new List<Movie>());
            Assert.Equal(0, svc.TotalEntries);
        }

        // ── Join Waitlist ─────────────────────────────────────

        [Fact]
        public void JoinWaitlist_ValidInput_CreatesEntry()
        {
            var entry = _service.JoinWaitlist(2, 10);
            Assert.NotNull(entry);
            Assert.Equal(2, entry.CustomerId);
            Assert.Equal("Bob", entry.CustomerName);
            Assert.Equal(10, entry.MovieId);
            Assert.Equal("Inception", entry.MovieName);
            Assert.Equal(WaitlistEntryStatus.Active, entry.Status);
        }

        [Fact]
        public void JoinWaitlist_PremiumCustomer_GetsPriorityPremium()
        {
            var entry = _service.JoinWaitlist(1, 10); // Alice = Platinum
            Assert.Equal(WaitlistPriority.Premium, entry.Priority);
        }

        [Fact]
        public void JoinWaitlist_GoldCustomer_GetsPriorityPremium()
        {
            var entry = _service.JoinWaitlist(3, 10); // Carol = Gold
            Assert.Equal(WaitlistPriority.Premium, entry.Priority);
        }

        [Fact]
        public void JoinWaitlist_BasicCustomer_GetsStandardPriority()
        {
            var entry = _service.JoinWaitlist(2, 10); // Bob = Basic
            Assert.Equal(WaitlistPriority.Standard, entry.Priority);
        }

        [Fact]
        public void JoinWaitlist_SilverCustomer_GetsStandardPriority()
        {
            var entry = _service.JoinWaitlist(4, 10); // Dave = Silver
            Assert.Equal(WaitlistPriority.Standard, entry.Priority);
        }

        [Fact]
        public void JoinWaitlist_UnknownCustomer_Throws()
        {
            Assert.Throws<ArgumentException>(() => _service.JoinWaitlist(99, 10));
        }

        [Fact]
        public void JoinWaitlist_UnknownMovie_Throws()
        {
            Assert.Throws<ArgumentException>(() => _service.JoinWaitlist(1, 99));
        }

        [Fact]
        public void JoinWaitlist_Duplicate_Throws()
        {
            _service.JoinWaitlist(2, 10);
            Assert.Throws<InvalidOperationException>(() => _service.JoinWaitlist(2, 10));
        }

        [Fact]
        public void JoinWaitlist_AfterLeaving_AllowsRejoin()
        {
            _service.JoinWaitlist(2, 10);
            _service.LeaveWaitlist(2, 10);
            var entry = _service.JoinWaitlist(2, 10);
            Assert.NotNull(entry);
            Assert.Equal(WaitlistEntryStatus.Active, entry.Status);
        }

        [Fact]
        public void JoinWaitlist_MaxSizeReached_Throws()
        {
            _service.MaxWaitlistSizePerMovie = 2;
            _service.JoinWaitlist(1, 10);
            _service.JoinWaitlist(2, 10);
            Assert.Throws<InvalidOperationException>(() => _service.JoinWaitlist(3, 10));
        }

        [Fact]
        public void JoinWaitlist_UnlimitedSize_AllowsMany()
        {
            _service.MaxWaitlistSizePerMovie = 0; // unlimited
            _service.JoinWaitlist(1, 10);
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(3, 10);
            _service.JoinWaitlist(4, 10);
            _service.JoinWaitlist(5, 10);
            Assert.Equal(5, _service.GetWaitlist(10).Count);
        }

        [Fact]
        public void JoinWaitlist_DifferentMovies_NoDuplicateConflict()
        {
            _service.JoinWaitlist(2, 10);
            var entry = _service.JoinWaitlist(2, 20);
            Assert.NotNull(entry);
            Assert.Equal(20, entry.MovieId);
        }

        // ── Leave Waitlist ────────────────────────────────────

        [Fact]
        public void LeaveWaitlist_ExistingEntry_ReturnsTrue()
        {
            _service.JoinWaitlist(2, 10);
            Assert.True(_service.LeaveWaitlist(2, 10));
        }

        [Fact]
        public void LeaveWaitlist_SetsStatusCancelled()
        {
            var entry = _service.JoinWaitlist(2, 10);
            _service.LeaveWaitlist(2, 10);
            var updated = _service.GetEntry(entry.Id);
            Assert.Equal(WaitlistEntryStatus.Cancelled, updated.Status);
            Assert.NotNull(updated.CancelledAt);
        }

        [Fact]
        public void LeaveWaitlist_NotOnList_ReturnsFalse()
        {
            Assert.False(_service.LeaveWaitlist(2, 10));
        }

        [Fact]
        public void CancelEntry_ValidActive_ReturnsTrue()
        {
            var entry = _service.JoinWaitlist(2, 10);
            Assert.True(_service.CancelEntry(entry.Id));
        }

        [Fact]
        public void CancelEntry_AlreadyCancelled_ReturnsFalse()
        {
            var entry = _service.JoinWaitlist(2, 10);
            _service.CancelEntry(entry.Id);
            Assert.False(_service.CancelEntry(entry.Id));
        }

        [Fact]
        public void CancelEntry_InvalidId_ReturnsFalse()
        {
            Assert.False(_service.CancelEntry(999));
        }

        // ── Position Tracking ─────────────────────────────────

        [Fact]
        public void GetPosition_FirstInLine_ReturnsOne()
        {
            _service.JoinWaitlist(2, 10);
            Assert.Equal(1, _service.GetPosition(2, 10));
        }

        [Fact]
        public void GetPosition_SecondInLine_ReturnsTwo()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);
            Assert.Equal(2, _service.GetPosition(4, 10));
        }

        [Fact]
        public void GetPosition_NotOnList_ReturnsNegativeOne()
        {
            Assert.Equal(-1, _service.GetPosition(2, 10));
        }

        [Fact]
        public void GetPosition_PremiumJumpsAheadOfStandard()
        {
            _service.JoinWaitlist(2, 10); // Bob = Basic (Standard)
            _service.JoinWaitlist(1, 10); // Alice = Platinum (Premium)
            Assert.Equal(1, _service.GetPosition(1, 10)); // Alice first
            Assert.Equal(2, _service.GetPosition(2, 10)); // Bob second
        }

        [Fact]
        public void GetWaitlist_OrdersPremiumFirst()
        {
            _service.JoinWaitlist(2, 10); // Standard
            _service.JoinWaitlist(5, 10); // Standard
            _service.JoinWaitlist(3, 10); // Premium (Gold)
            _service.JoinWaitlist(1, 10); // Premium (Platinum)

            var list = _service.GetWaitlist(10);
            Assert.Equal(4, list.Count);
            // Premium members first (ordered by join time among themselves)
            Assert.Equal(WaitlistPriority.Premium, list[0].Priority);
            Assert.Equal(WaitlistPriority.Premium, list[1].Priority);
            Assert.Equal(WaitlistPriority.Standard, list[2].Priority);
            Assert.Equal(WaitlistPriority.Standard, list[3].Priority);
        }

        [Fact]
        public void GetWaitlist_EmptyMovie_ReturnsEmpty()
        {
            Assert.Empty(_service.GetWaitlist(10));
        }

        [Fact]
        public void GetEntry_ValidId_ReturnsEntry()
        {
            var entry = _service.JoinWaitlist(2, 10);
            Assert.NotNull(_service.GetEntry(entry.Id));
        }

        [Fact]
        public void GetEntry_InvalidId_ReturnsNull()
        {
            Assert.Null(_service.GetEntry(999));
        }

        // ── Wait Time Estimation ──────────────────────────────

        [Fact]
        public void EstimateWaitDays_FirstPosition_ReturnsAvgDuration()
        {
            _service.JoinWaitlist(2, 10);
            var wait = _service.EstimateWaitDays(2, 10);
            Assert.Equal(3.0, wait); // position 1 * 3.0 avg
        }

        [Fact]
        public void EstimateWaitDays_SecondPosition_ReturnsDouble()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);
            Assert.Equal(6.0, _service.EstimateWaitDays(4, 10)); // position 2 * 3.0
        }

        [Fact]
        public void EstimateWaitDays_NotOnList_Throws()
        {
            Assert.Throws<InvalidOperationException>(() =>
                _service.EstimateWaitDays(2, 10));
        }

        [Fact]
        public void EstimateWaitDays_CustomAvgDuration_UsesConfigured()
        {
            _service.AverageRentalDurationDays = 5.0;
            _service.JoinWaitlist(2, 10);
            Assert.Equal(5.0, _service.EstimateWaitDays(2, 10));
        }

        [Fact]
        public void EstimateWaitDaysForNewJoiner_EmptyList_ReturnsOnePeriod()
        {
            var wait = _service.EstimateWaitDaysForNewJoiner(10);
            Assert.Equal(3.0, wait); // (0 + 1) * 3.0
        }

        [Fact]
        public void EstimateWaitDaysForNewJoiner_WithExisting_AccountsForQueue()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);
            var wait = _service.EstimateWaitDaysForNewJoiner(10);
            Assert.Equal(9.0, wait); // (2 + 1) * 3.0
        }

        // ── Auto-Notify ───────────────────────────────────────

        [Fact]
        public void NotifyNextCustomer_NotifiesFirst()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);

            var notification = _service.NotifyNextCustomer(10);
            Assert.NotNull(notification);
            Assert.Equal(2, notification.CustomerId);
            Assert.Equal("Bob", notification.CustomerName);
            Assert.Contains("Inception", notification.Message);
        }

        [Fact]
        public void NotifyNextCustomer_SetsEntryToNotified()
        {
            var entry = _service.JoinWaitlist(2, 10);
            _service.NotifyNextCustomer(10);

            var updated = _service.GetEntry(entry.Id);
            Assert.Equal(WaitlistEntryStatus.Notified, updated.Status);
            Assert.NotNull(updated.NotifiedAt);
        }

        [Fact]
        public void NotifyNextCustomer_EmptyWaitlist_ReturnsNull()
        {
            Assert.Null(_service.NotifyNextCustomer(10));
        }

        [Fact]
        public void NotifyNextCustomer_SkipsAlreadyNotified()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);

            _service.NotifyNextCustomer(10); // Notifies Bob
            var second = _service.NotifyNextCustomer(10); // Should notify Dave
            Assert.Equal(4, second.CustomerId);
        }

        [Fact]
        public void NotifyNextCustomer_PremiumGoesFirst()
        {
            _service.JoinWaitlist(2, 10); // Standard
            _service.JoinWaitlist(1, 10); // Premium

            var notification = _service.NotifyNextCustomer(10);
            Assert.Equal(1, notification.CustomerId); // Alice (premium) first
        }

        [Fact]
        public void FulfillEntry_NotifiedEntry_ReturnsTrue()
        {
            var entry = _service.JoinWaitlist(2, 10);
            _service.NotifyNextCustomer(10);
            Assert.True(_service.FulfillEntry(entry.Id));

            var updated = _service.GetEntry(entry.Id);
            Assert.Equal(WaitlistEntryStatus.Fulfilled, updated.Status);
            Assert.NotNull(updated.FulfilledAt);
        }

        [Fact]
        public void FulfillEntry_ActiveEntry_ReturnsFalse()
        {
            var entry = _service.JoinWaitlist(2, 10);
            Assert.False(_service.FulfillEntry(entry.Id)); // not notified yet
        }

        [Fact]
        public void FulfillEntry_InvalidId_ReturnsFalse()
        {
            Assert.False(_service.FulfillEntry(999));
        }

        [Fact]
        public void GetNotifications_ReturnsForMovie()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);
            _service.NotifyNextCustomer(10);
            _service.NotifyNextCustomer(10);

            var notifications = _service.GetNotifications(10);
            Assert.Equal(2, notifications.Count);
        }

        [Fact]
        public void GetNotifications_DifferentMovies_Isolated()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 20);
            _service.NotifyNextCustomer(10);
            _service.NotifyNextCustomer(20);

            Assert.Single(_service.GetNotifications(10));
            Assert.Single(_service.GetNotifications(20));
        }

        // ── History ───────────────────────────────────────────

        [Fact]
        public void GetCustomerHistory_ReturnsAllStatuses()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(2, 20);
            _service.LeaveWaitlist(2, 20);

            var history = _service.GetCustomerHistory(2);
            Assert.Equal(2, history.Count);
        }

        [Fact]
        public void GetFulfilledHistory_OnlyFulfilled()
        {
            var entry = _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(2, 20);
            _service.NotifyNextCustomer(10);
            _service.FulfillEntry(entry.Id);

            var fulfilled = _service.GetFulfilledHistory(2);
            Assert.Single(fulfilled);
            Assert.Equal(10, fulfilled[0].MovieId);
        }

        [Fact]
        public void GetActiveEntriesForCustomer_ExcludesCancelled()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(2, 20);
            _service.LeaveWaitlist(2, 20);

            var active = _service.GetActiveEntriesForCustomer(2);
            Assert.Single(active);
            Assert.Equal(10, active[0].MovieId);
        }

        // ── Movie Stats ──────────────────────────────────────

        [Fact]
        public void GetMovieStats_ReturnsCorrectCounts()
        {
            _service.JoinWaitlist(1, 10); // Premium
            _service.JoinWaitlist(2, 10); // Standard
            _service.JoinWaitlist(3, 10); // Premium

            var stats = _service.GetMovieStats(10);
            Assert.Equal(3, stats.CurrentSize);
            Assert.Equal(2, stats.PremiumCount);
            Assert.Equal(1, stats.StandardCount);
            Assert.Equal("Inception", stats.MovieName);
        }

        [Fact]
        public void GetMovieStats_UnknownMovie_Throws()
        {
            Assert.Throws<ArgumentException>(() => _service.GetMovieStats(99));
        }

        [Fact]
        public void GetMovieStats_DemandScore_CalculatedCorrectly()
        {
            _service.MaxWaitlistSizePerMovie = 10;
            _service.JoinWaitlist(1, 10);
            _service.JoinWaitlist(2, 10);

            var stats = _service.GetMovieStats(10);
            Assert.Equal(0.2, stats.DemandScore); // 2/10
        }

        [Fact]
        public void GetMovieStats_EmptyWaitlist_ZeroDemand()
        {
            var stats = _service.GetMovieStats(10);
            Assert.Equal(0, stats.CurrentSize);
            Assert.Equal(0.0, stats.DemandScore);
        }

        [Fact]
        public void GetAllMovieStats_ReturnsOnlyMoviesWithWaiters()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 20);

            var all = _service.GetAllMovieStats();
            Assert.Equal(2, all.Count);
        }

        [Fact]
        public void GetAllMovieStats_OrderedByDemandDescending()
        {
            _service.JoinWaitlist(1, 10);
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(3, 10);
            _service.JoinWaitlist(4, 20);

            var all = _service.GetAllMovieStats();
            Assert.True(all[0].DemandScore >= all[1].DemandScore);
        }

        // ── Bulk Operations ───────────────────────────────────

        [Fact]
        public void ClearMovieWaitlist_CancelsAllActive()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 10);

            var cleared = _service.ClearMovieWaitlist(10);
            Assert.Equal(2, cleared);
            Assert.Empty(_service.GetWaitlist(10));
        }

        [Fact]
        public void ClearMovieWaitlist_DoesNotAffectOtherMovies()
        {
            _service.JoinWaitlist(2, 10);
            _service.JoinWaitlist(4, 20);

            _service.ClearMovieWaitlist(10);
            Assert.Single(_service.GetWaitlist(20));
        }

        [Fact]
        public void PurgeOldEntries_RemovesCancelledAndExpired()
        {
            _service.JoinWaitlist(2, 10);
            _service.LeaveWaitlist(2, 10);

            var purged = _service.PurgeOldEntries(0);
            Assert.Equal(1, purged);
            Assert.Equal(0, _service.TotalEntries);
        }

        [Fact]
        public void PurgeOldEntries_NegativeDays_Throws()
        {
            Assert.Throws<ArgumentException>(() => _service.PurgeOldEntries(-1));
        }

        [Fact]
        public void PurgeOldEntries_DoesNotRemoveActive()
        {
            _service.JoinWaitlist(2, 10);
            var purged = _service.PurgeOldEntries(0);
            Assert.Equal(0, purged);
            Assert.Equal(1, _service.TotalEntries);
        }

        // ── Counts ────────────────────────────────────────────

        [Fact]
        public void TotalEntries_TracksAll()
        {
            Assert.Equal(0, _service.TotalEntries);
            _service.JoinWaitlist(2, 10);
            Assert.Equal(1, _service.TotalEntries);
            _service.JoinWaitlist(4, 10);
            Assert.Equal(2, _service.TotalEntries);
        }

        [Fact]
        public void TotalNotifications_TracksAll()
        {
            _service.JoinWaitlist(2, 10);
            Assert.Equal(0, _service.TotalNotifications);
            _service.NotifyNextCustomer(10);
            Assert.Equal(1, _service.TotalNotifications);
        }

        // ── WaitlistEntry Model ───────────────────────────────

        [Fact]
        public void WaitlistEntry_WaitDays_CalculatesCorrectly()
        {
            var entry = new WaitlistEntry
            {
                JoinedAt = DateTime.Now.AddDays(-5),
                FulfilledAt = DateTime.Now
            };
            Assert.True(entry.WaitDays >= 4.9 && entry.WaitDays <= 5.1);
        }

        [Fact]
        public void WaitlistEntry_WaitDays_NeverNegative()
        {
            var entry = new WaitlistEntry
            {
                JoinedAt = DateTime.Now.AddDays(1),
                FulfilledAt = DateTime.Now
            };
            Assert.Equal(0, entry.WaitDays);
        }
    }
}

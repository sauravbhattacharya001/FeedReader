using System;
using System.ComponentModel.DataAnnotations;

namespace Vidly.Models
{
    public class Movie
    {
        public int Id { get; set; }

        [Required(ErrorMessage = "Movie name is required.")]
        [StringLength(255, ErrorMessage = "Movie name cannot exceed 255 characters.")]
        public string Name { get; set; }

        [Display(Name = "Release Date")]
        [DataType(DataType.Date)]
        public DateTime? ReleaseDate { get; set; }

        [Display(Name = "Genre")]
        public Genre? Genre { get; set; }

        [Display(Name = "Rating")]
        [Range(1, 5, ErrorMessage = "Rating must be between 1 and 5.")]
        public int? Rating { get; set; }

        /// <summary>
        /// Optional per-movie daily rate override.
        /// </summary>
        [Display(Name = "Daily Rate")]
        [Range(0.01, 99.99, ErrorMessage = "Daily rate must be between $0.01 and $99.99.")]
        public decimal? DailyRate { get; set; }

        /// <summary>
        /// Whether this movie is considered a new release (within 90 days).
        /// </summary>
        public bool IsNewRelease =>
            ReleaseDate.HasValue &&
            (DateTime.Today - ReleaseDate.Value).TotalDays <= 90;
    }

    public enum Genre
    {
        Action = 1,
        Comedy = 2,
        Drama = 3,
        Horror = 4,
        SciFi = 5,
        Romance = 6,
        Documentary = 7,
        Thriller = 8
    }
}

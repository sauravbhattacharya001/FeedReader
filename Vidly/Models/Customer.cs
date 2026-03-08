using System;
using System.ComponentModel.DataAnnotations;

namespace Vidly.Models
{
    public class Customer
    {
        public int Id { get; set; }

        [Required(ErrorMessage = "Customer name is required.")]
        [StringLength(255, ErrorMessage = "Customer name cannot exceed 255 characters.")]
        public string Name { get; set; }

        [EmailAddress(ErrorMessage = "Invalid email address.")]
        [StringLength(255, ErrorMessage = "Email cannot exceed 255 characters.")]
        public string Email { get; set; }

        [Phone(ErrorMessage = "Invalid phone number.")]
        [StringLength(20, ErrorMessage = "Phone number cannot exceed 20 characters.")]
        public string Phone { get; set; }

        [Display(Name = "Member Since")]
        [DataType(DataType.Date)]
        public DateTime? MemberSince { get; set; }

        [Display(Name = "Membership Type")]
        public MembershipType MembershipType { get; set; }
    }

    /// <summary>
    /// Customer membership tier.
    /// </summary>
    public enum MembershipType
    {
        [Display(Name = "Basic")]
        Basic = 1,

        [Display(Name = "Silver")]
        Silver = 2,

        [Display(Name = "Gold")]
        Gold = 3,

        [Display(Name = "Platinum")]
        Platinum = 4
    }
}

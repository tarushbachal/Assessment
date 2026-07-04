"""
One function to be called that cleans CSV which was imported from .mdb file.
    1. Appointment date had fake time placeholder
    2. Appointment time had fake date placeholder
    3. Show code = Y stored as is_completed
    4. Show code = N or P stored as is_noshow
    5. defines after-hours and telephone appointments
    6. variables for lead days and lead minutes are created
"""

import pandas as pd


# After-hours means the appointment is at 5:30 PM or later.
# We measure time as "minutes since midnight", so 17:30 = 17*60 + 30 = 1050.
AFTER_HOURS_MIN = 1050

# The CSV sits one folder up from this file (in the Assessment folder).
import os
CSV_PATH = os.path.join(os.path.dirname(__file__), "..", "Appointment Data.csv")


def load_clean(csv_path=CSV_PATH):
    # Read everything as text first so the weird date/time strings don't get
    # auto-parsed into the wrong thing.
    df = pd.read_csv(csv_path, dtype=str)

    # --- Fix the dates and times -------------------------------------------
    # The date columns look like "12/04/09 00:00:00" -> the time part is fake,
    # so we only keep the date (the first word).
    # The time columns look like "12/30/99 17:30:00" -> the date part is fake,
    # so we only keep the time (the second word).
    df["appt_date"] = pd.to_datetime(df["APPOINTMENT_DATE"].str[:8], format="%m/%d/%y")
    df["booking_date"] = pd.to_datetime(df["BOOKING_DATE"].str[:8], format="%m/%d/%y")

    appt_time = pd.to_datetime(df["APPOINTMENT_TIME"].str[-8:], format="%H:%M:%S")
    booking_time = pd.to_datetime(df["BOOKING_TIME"].str[-8:], format="%H:%M:%S")

    # Turn the clock time into minutes from midnight ( to compare/group).
    df["appt_min_of_day"] = appt_time.dt.hour * 60 + appt_time.dt.minute
    df["appt_hour"] = appt_time.dt.hour
    df["booking_min_of_day"] = booking_time.dt.hour * 60 + booking_time.dt.minute

    # Helpful calendar columns.
    df["day_of_week"] = df["appt_date"].dt.day_name()
    df["appt_month"] = df["appt_date"].dt.strftime("%Y-%m")

    # --- Flags we use all over the analysis --------------------------------
    df["is_telephone"] = df["APPOINTMENT_TYPE"] == "Telephone Visit"
    df["is_after_hours"] = df["appt_min_of_day"] >= AFTER_HOURS_MIN
    df["is_weekend"] = df["day_of_week"].isin(["Saturday", "Sunday"])

    # Show code: Y = patient showed up, N or P = no-show (from the data dictionary).
    df["is_completed"] = df["SHOW_CODE"] == "Y"
    df["is_noshow"] = df["SHOW_CODE"].isin(["N", "P"])

    # --- How early was the appointment booked? -----------------------------
    df["lead_days"] = (df["appt_date"] - df["booking_date"]).dt.days
    # For same-day bookings, how many minutes before the appointment was it booked.
    df["booking_lead_min"] = df["appt_min_of_day"] - df["booking_min_of_day"]
    df.loc[df["lead_days"] != 0, "booking_lead_min"] = None

    return df


if __name__ == "__main__":
    df = load_clean()
    after_hours_phone = df[df["is_telephone"] & df["is_after_hours"]]
    print("Total rows:", len(df))
    print("After-hours telephone appointments:", len(after_hours_phone))
    print("Date range:", df["appt_date"].min().date(), "to", df["appt_date"].max().date())
